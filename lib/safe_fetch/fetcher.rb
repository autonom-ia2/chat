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
        content_type: normalized_content_type(response['content-type'])
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
      next if res.is_a?(Net::HTTPRedirection) && options.follow_redirects?
      raise http_error(res) unless res.is_a?(Net::HTTPSuccess)

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

  def http_error(response)
    SafeFetch::HttpError.new("#{response.code} #{response.message}", status: response.code.to_i)
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
  # real ("waiting only what is left of the total"), que reprova se este acoplamento deixar de valer.
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
end
