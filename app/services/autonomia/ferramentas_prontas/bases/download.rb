# O DOWNLOAD DE UMA BASE (#2858, F5), sobre o `SafeFetch` (o mesmo das ferramentas): por streaming, direto para um
# arquivo temporário, com teto de tamanho (no anúncio e na leitura) e prazo total.
#
# Proteções: só HTTPS na 443, só os hosts do importador (o endereço é conferido antes de sair), redirecionamento só para
# a mesma origem, IP privado barrado pelo `SafeFetch` em cada salto. Erro vira `Bases::Falha` com motivo curto
# (`tempo_esgotado`, `arquivo_grande_demais`, `erro_da_fonte`...): a mensagem de fora nunca vai ao log nem ao alerta.
#
# `baixar` devolve um `Tempfile` que já não depende do `SafeFetch` (que apaga o dele ao sair do bloco): quem chamou
# fecha com `close!` (a `Importacao` fecha todos no fim).
class Autonomia::FerramentasProntas::Bases::Download
  Falha = Autonomia::FerramentasProntas::Bases::Falha

  PORTA = 443
  MAX_REDIRECTS = 2
  ABERTURA = 10
  LEITURA = 60
  MAX_JSON = 2.megabytes
  CABECALHOS = { 'Accept-Encoding' => 'identity', 'User-Agent' => 'Autonomia-FerramentasProntas/1.0' }.freeze
  MOTIVOS = [
    [SafeFetch::TotalTimeoutError, 'tempo_esgotado'],
    [SafeFetch::CrossOriginRedirectError, 'redirecionou_para_fora'],
    [SafeFetch::FileTooLargeError, 'arquivo_grande_demais'],
    [SafeFetch::UnsafeUrlError, 'endereco_recusado'],
    [SafeFetch::InvalidUrlError, 'endereco_recusado'],
    [SafeFetch::UnsupportedContentTypeError, 'formato_mudou']
  ].freeze
  TRANSPORTE = [Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, SystemCallError, IOError,
                OpenSSL::SSL::SSLError, Resolv::ResolvError, Timeout::Error].freeze

  attr_reader :chamadas

  def initialize(hosts:)
    @hosts = hosts.map(&:downcase)
    @chamadas = 0
  end

  # -> o arquivo baixado (Tempfile, binário, no começo). `nao_encontrado: :nil` devolve nil no 404 (o arquivo do dia
  # que ainda não saiu), em vez de falhar.
  def baixar(url, max_bytes:, prazo:, nao_encontrado: :falha)
    conferir!(url)
    @chamadas += 1
    SafeFetch.fetch(url, **opcoes(max_bytes, prazo)) { |resultado| return copiar(resultado.tempfile) }
  rescue SafeFetch::HttpError => e
    return nil if e.status.to_i == 404 && nao_encontrado == :nil

    raise Falha, falha_http(e.status.to_i)
  rescue SafeFetch::Error, *TRANSPORTE => e
    raise Falha, motivo(e)
  end

  # -> o JSON pequeno de um catálogo de dados abertos (o da ANTT diz qual é o arquivo do mês).
  def json(url, prazo: 30)
    arquivo = baixar(url, max_bytes: MAX_JSON, prazo: prazo)
    JSON.parse(arquivo.read)
  rescue JSON::ParserError, EncodingError
    raise Falha, 'formato_mudou'
  ensure
    arquivo&.close!
  end

  def conferir!(url)
    destino = URI.parse(url.to_s)
    raise Falha, 'host_fora_da_lista' unless destino.is_a?(URI::HTTPS) && @hosts.include?(destino.host.to_s.downcase)
    raise Falha, 'host_fora_da_lista' unless destino.port == PORTA && destino.userinfo.nil?
  rescue URI::InvalidURIError
    raise Falha, 'endereco_recusado'
  end

  private

  def copiar(origem)
    arquivo = Tempfile.new('autonomia-base', binmode: true)
    IO.copy_stream(origem, arquivo)
    arquivo.rewind
    arquivo
  end

  def opcoes(max_bytes, prazo)
    {
      method: :get, headers: CABECALHOS, max_bytes: max_bytes, open_timeout: ABERTURA, read_timeout: LEITURA,
      total_timeout: prazo, max_redirects: MAX_REDIRECTS, cross_origin_redirects: false, allowed_ports: [PORTA],
      schemes: %w[https], validate_content_type: false
    }
  end

  def motivo(erro)
    MOTIVOS.find { |classe, _motivo| erro.is_a?(classe) }&.last || 'falha_de_rede'
  end

  def falha_http(status)
    return 'nao_encontrado' if status == 404
    return 'limite_da_fonte' if status == 429
    return 'erro_da_fonte' if status >= 500

    'pedido_recusado'
  end
end
