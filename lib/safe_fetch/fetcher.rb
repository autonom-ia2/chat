class SafeFetch::Fetcher
  def initialize(options)
    @options = options
  end

  def fetch
    @deadline = SafeFetch::Deadline.new(options.total_timeout)
    with_tempfile do |tempfile|
      response = stream_response(tempfile)
      raise http_error(response) unless response.is_a?(Net::HTTPSuccess)

      tempfile.rewind
      yield SafeFetch::Result.new(
        tempfile: tempfile,
        filename: options.filename,
        content_type: normalized_content_type(response['content-type']),
        url: response.uri&.to_s || options.url.to_s,
        charset: charset_of(response['content-type'])
      )
    end
  end

  private

  attr_reader :options, :deadline

  def with_tempfile
    tempfile = Tempfile.new('chatwoot-safe-fetch', binmode: true)
    yield tempfile
  ensure
    tempfile&.close!
  end

  # O 3xx que o ssrf_filter vai seguir passa (o corpo dele é pequeno, e o salto seguinte é revalidado).
  # QUALQUER outra resposta que não é 2xx é recusada AQUI, dentro do bloco: depois do bloco o Net::HTTP
  # lê o corpo inteiro em memória (`reading_body` → `body`), a menos que o bloco levante — é o que
  # impede um 404 (ou um 302 não seguido) de tamanho arbitrário de ser materializado antes da recusa.
  def stream_response(tempfile)
    bytes_written = 0

    perform_request do |res|
      if res.is_a?(Net::HTTPRedirection) && options.follow_redirects?
        refuse_cross_origin_redirect!(res)
        next
      end
      raise http_error(res, error_excerpt(res)) unless res.is_a?(Net::HTTPSuccess)

      validate_content_type!(res['content-type'])
      validate_announced_size!(res['content-length'])
      bytes_written = write_response_body(res, tempfile, bytes_written)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError,
         IOError, Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET,
         Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EPIPE, Errno::ETIMEDOUT => e
    raise SafeFetch::TotalTimeoutError, deadline.exceeded_message if e.is_a?(Net::ReadTimeout) && deadline.binding?

    raise SafeFetch::FetchError, e.message
  end

  def perform_request(&)
    return SafeFetch::PrivateNetworkRequest.new(options).perform(&) if SafeFetch.allow_private_network?

    SsrfFilter.public_send(options.method, options.url, **options.request_options, &)
  end

  # `excerpt`: o que `error_excerpt` devolve — [trecho, cortou?], ou [] sem trecho.
  def http_error(response, excerpt = [])
    body_excerpt, truncated = excerpt
    SafeFetch::HttpError.new("#{response.code} #{response.message}",
                             status: response.code.to_i, body_excerpt: body_excerpt,
                             body_excerpt_truncated: truncated || false)
  end

  # Roda dentro do bloco, ANTES de o ssrf_filter seguir o salto: levantar aqui impede a requisição ao
  # destino. Sem `Location` não há salto, e o 3xx cai na recusa por status como sempre.
  def refuse_cross_origin_redirect!(response)
    location = response['location']
    return if options.cross_origin_redirects? || location.blank? || options.same_origin_location?(location)

    raise SafeFetch::CrossOriginRedirectError
  end

  # O começo do corpo de uma resposta de erro, até `error_body_bytes`, dentro do prazo. Parar de ler
  # no meio é seguro: quem chama levanta logo em seguida, ainda dentro do bloco, e a conexão é
  # descartada sem o Net::HTTP materializar o resto. Falha ao ler não troca o erro: vira sem trecho.
  # Lê um byte a mais que o teto para saber se cortou. -> [trecho, cortou?] ou [].
  def error_excerpt(response)
    limit = options.error_body_bytes
    return [] if limit.zero?

    excerpt = read_excerpt(response, limit)
    [excerpt.byteslice(0, limit).force_encoding(Encoding::UTF_8).scrub.presence, excerpt.bytesize > limit]
  rescue SafeFetch::Error, Net::ReadTimeout, IOError, SystemCallError, OpenSSL::SSL::SSLError
    []
  end

  def read_excerpt(response, limit)
    socket = response.instance_variable_get(:@socket)
    deadline.enforce!(socket)
    excerpt = String.new(encoding: Encoding::BINARY)
    response.read_body do |chunk|
      excerpt << chunk
      break if excerpt.bytesize > limit

      deadline.enforce!(socket)
    end
    excerpt
  end

  def validate_content_type!(content_type)
    return unless options.validate_content_type?
    return if allowed_content_type?(content_type)

    raise SafeFetch::UnsupportedContentTypeError, "content-type not allowed: #{content_type}"
  end

  # O tamanho anunciado reprova antes do primeiro byte: um `Content-Length` acima do teto não precisa
  # ser lido para ser recusado. O teto medido (abaixo) continua valendo para quem não anuncia.
  def validate_announced_size!(content_length)
    return if content_length.blank? || content_length.to_i <= options.effective_max_bytes

    raise SafeFetch::FileTooLargeError, "announced #{content_length.to_i} bytes, limit #{options.effective_max_bytes}"
  end

  # O socket da resposta é o `Net::BufferedIO` da conexão enquanto o corpo é lido: é onde vive o
  # `read_timeout` que cada espera consulta. O Net::HTTP (net-http 0.9.1) não o expõe, e apertá-lo é a
  # única alavanca por leitura que existe sem trocar o cliente HTTP; a guarda é o spec com servidor
  # real ("waiting only what is left of the total"), que reprova se este acoplamento deixar de valer —
  # e, em produção, o `Deadline` registra (`sem_socket`) se um dia o ivar vier nil. O prazo daqui é o
  # do CORPO com teto por leitura: entre dois `enforce!` o `read_body` pode fazer mais de uma leitura
  # (as linhas de controle do chunked), cada uma com o teto do saldo (ressalva, `SafeFetch::Deadline`).
  def write_response_body(response, tempfile, bytes_written)
    socket = response.instance_variable_get(:@socket)
    deadline.enforce!(socket)
    response.read_body do |chunk|
      bytes_written += chunk.bytesize
      raise SafeFetch::FileTooLargeError, "exceeded #{options.effective_max_bytes} bytes" if bytes_written > options.effective_max_bytes

      tempfile.write(chunk)
      deadline.enforce!(socket)
    end

    bytes_written
  end

  def allowed_content_type?(value)
    mime = normalized_content_type(value)
    return false if mime.blank?

    options.allowed_content_type_prefixes.any? { |prefix| mime.start_with?(prefix) } ||
      options.allowed_content_types.include?(mime)
  end

  def normalized_content_type(value)
    value.to_s.split(';').first&.strip&.downcase
  end

  # "text/html; charset=ISO-8859-1" → "iso-8859-1".
  def charset_of(value)
    param = value.to_s.split(';').drop(1).map(&:strip).find { |part| part.downcase.start_with?('charset=') }
    param && param.split('=', 2).last.strip.delete('"\'').downcase.presence
  end
end
