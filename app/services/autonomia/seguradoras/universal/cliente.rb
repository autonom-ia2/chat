# Cliente HTTP da API da Universal Assistance (#3211). Só transporte: monta o pedido, traduz o status em um dos
# códigos de `Codigos::TODOS` e devolve o JSON. Quem decide o que fazer com o erro é quem chama.
#
# O log tem uma linha por chamada e nunca leva cabeçalho, corpo, login, URL com query nem a mensagem de exceção:
# o corpo da compra traz CPF e o cabeçalho traz a senha do corretor.
class Autonomia::Seguradoras::Universal::Cliente
  BASE_URL = 'https://api-br.universal-assistance.com'.freeze
  # O Setup roda dentro da requisição da tela (conferir o acesso, abaixo do Rack::Timeout de 15 s). O `open_timeout` do
  # Net::HTTP vale para a conexão TCP e para o handshake SSL juntos, então o pior caso sem resposta do Setup é
  # ABERTURA + LEITURA (3 + 8 = 11 s). O `read_timeout` vale por leitura, não pelo total: uma resposta que pinga devagar
  # pode passar disso. `max_retries = 0` vale para todas as chamadas, não só para o Setup: o Net::HTTP repetiria uma vez
  # um GET que estourou a leitura (Setup e destinos), dobrando a espera; os POST ele já não repete. As outras chamadas
  # rodam no turno do agente, em job.
  ABERTURA = 3
  LEITURA = { setup: 8, destinos: 15, cotar: 40, comprar: 40 }.freeze
  MENSAGEM_MAXIMA = 200
  STATUS_RECUSADO = [401, 403].freeze
  STATUS_INVALIDO = [400, 404, 409, 422].freeze
  FALHAS_DE_REDE = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError,
                    OpenSSL::SSL::SSLError, Net::HTTPBadResponse].freeze

  class Erro < StandardError
    attr_reader :codigo, :mensagem_da_seguradora

    def initialize(codigo, mensagem_da_seguradora: nil)
      super(codigo)
      @codigo = codigo
      @mensagem_da_seguradora = mensagem_da_seguradora
    end
  end

  def self.base_url
    ENV.fetch('UNIVERSAL_API_BASE_URL', BASE_URL)
  end

  def initialize(login:, senha:)
    @login = login
    @senha = senha
  end

  def setup
    chamar(:setup, Net::HTTP::Get, '/v1/Emissor/Setup')
  end

  def destinos
    chamar(:destinos, Net::HTTP::Get, '/v1/destinos')
  end

  def cotar(pedido)
    chamar(:cotar, Net::HTTP::Post, '/v1/Cotacao', pedido)
  end

  def comprar(pedido)
    chamar(:comprar, Net::HTTP::Post, '/v1/Compras', pedido)
  end

  private

  def chamar(nome, metodo, caminho, corpo = nil)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    resposta = executar(nome, montar(metodo, caminho, corpo))
    registrar(nome, resposta.code, inicio)
    interpretar(resposta)
  rescue *FALHAS_DE_REDE
    registrar(nome, 'sem_resposta', inicio)
    raise Erro, Autonomia::Seguradoras::Universal::Codigos::INDISPONIVEL
  end

  def montar(metodo, caminho, corpo)
    requisicao = metodo.new(URI("#{self.class.base_url}#{caminho}"))
    requisicao['Login'] = @login
    requisicao['Senha'] = @senha
    requisicao['Content-Type'] = 'application/json'
    requisicao['Accept'] = 'application/json'
    requisicao.body = JSON.generate(corpo) unless corpo.nil?
    requisicao
  end

  def executar(nome, requisicao)
    uri = requisicao.uri
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = ABERTURA
    http.read_timeout = LEITURA.fetch(nome)
    http.max_retries = 0
    http.request(requisicao)
  end

  def interpretar(resposta)
    status = resposta.code.to_i
    return lido(resposta.body) if status.between?(200, 299)
    raise Erro, Autonomia::Seguradoras::Universal::Codigos::ACESSO_RECUSADO if STATUS_RECUSADO.include?(status)

    if STATUS_INVALIDO.include?(status)
      raise Erro.new(Autonomia::Seguradoras::Universal::Codigos::PEDIDO_INVALIDO,
                     mensagem_da_seguradora: mensagem_do(resposta.body))
    end

    raise Erro, Autonomia::Seguradoras::Universal::Codigos::INDISPONIVEL
  end

  def lido(texto)
    JSON.parse(texto.to_s)
  rescue JSON::ParserError
    raise Erro, Autonomia::Seguradoras::Universal::Codigos::INDISPONIVEL
  end

  def mensagem_do(texto)
    corpo = JSON.parse(texto.to_s)
    corpo.is_a?(Hash) ? corpo['message'].to_s.first(MENSAGEM_MAXIMA).presence : nil
  rescue JSON::ParserError
    nil
  end

  def registrar(nome, status, inicio)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    Rails.logger.info("[autonomia][universal] chamada=#{nome} status=#{status} ms=#{ms}")
  end
end
