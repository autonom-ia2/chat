# Cliente HTTP da API da Universal Assistance (#3211). Só transporte: monta o pedido, traduz o status em um dos
# códigos de `Codigos::TODOS` e devolve o JSON. Quem decide o que fazer com o erro é quem chama. A exceção é o catálogo
# de coberturas (`beneficios`, #3249), que é guardado aqui por um dia.
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
  LEITURA = { setup: 8, destinos: 15, cotar: 40, comprar: 40, status_do_pagamento: 15, url_do_voucher: 15,
              beneficios: 15 }.freeze
  MENSAGEM_MAXIMA = 200
  STATUS_RECUSADO = [401, 403].freeze
  STATUS_INVALIDO = [400, 404, 409, 422].freeze
  FALHAS_DE_REDE = [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET,
                    Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT, EOFError, IOError,
                    OpenSSL::SSL::SSLError, Net::HTTPBadResponse].freeze
  # O voucher pedido pelo carrinho, em português, no formato que a Universal imprime (`b`) (#3246).
  CONSULTA_DO_VOUCHER = 'tipoParametro=idCarrinho&tipoImpressao=b&idioma=portugues'.freeze
  DIGITOS = ('0'..'9')
  # Separação de domínio do resumo do login (`emissor`): a chave do HMAC é derivada só para isto.
  DOMINIO_DO_EMISSOR = 'universal/emissor'.freeze
  # O catálogo de coberturas dos planos (#3249), em português e na tarifa 1, guardado por um dia por emissor e por tipo
  # de viagem (nacional ou internacional). A chave leva o `emissor`, nunca o login nem a senha.
  CONSULTA_DOS_BENEFICIOS = 'idioma=portugues&tipoTarifa=1'.freeze
  CHAVE_DOS_BENEFICIOS = 'autonomia:universal:beneficios:v1:'.freeze
  VALIDADE_DOS_BENEFICIOS = 1.day

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

  # Um resumo do login (HMAC, 16 caracteres) para separar o que fica guardado por emissor, como a lista de destinos.
  # Nunca o login: a chave de cache vai para o Redis e para log.
  def emissor
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.key_generator.generate_key(DOMINIO_DO_EMISSOR), @login.to_s).first(16)
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

  # #3246: a situação do pagamento do carrinho (`statusPagamento`: "Pago", "Aguardando Pagamento", "" ou "Cancelado").
  # Carrinho inexistente a Universal responde 500 (`indisponivel`).
  def status_do_pagamento(carrinho)
    chamar(:status_do_pagamento, Net::HTTP::Get, "/v1/StatusPagamento/#{carrinho!(carrinho)}")
  end

  # #3246: -> `{ "url" => <endereço do PDF do voucher> }`. O voucher que não existe volta 400 com texto puro
  # (`pedido_invalido`, sem mensagem). A URL responde PDF só com o pagamento feito; antes, um JSON.
  def url_do_voucher(carrinho)
    chamar(:url_do_voucher, Net::HTTP::Get, "/v1/Voucher/imprimir/#{carrinho!(carrinho)}?#{CONSULTA_DO_VOUCHER}")
  end

  # #3249: o catálogo de coberturas de cada plano, sem preço: `{ "beneficios" => [{ idBeneficio, descricao }],
  # "produtos" => [{ descricao, beneficios: [{ idBeneficio, valor }] }] }`. Guardado por um dia: muda pouco, e a
  # pergunta de cobertura antes da cotação não pode esperar a Universal a cada turno. A falha levanta e não fica
  # guardada; o catálogo sem plano conta como falha (`indisponivel`), para um dia inteiro não responder "não existe".
  def beneficios(nacional:)
    nacional = nacional == true
    chave = "#{CHAVE_DOS_BENEFICIOS}#{emissor}:#{nacional ? 'nacional' : 'internacional'}"
    Rails.cache.fetch(chave, expires_in: VALIDADE_DOS_BENEFICIOS) do
      catalogo = chamar(:beneficios, Net::HTTP::Get, "/v1/beneficios?#{CONSULTA_DOS_BENEFICIOS}&nacional=#{nacional}")
      raise Erro, Autonomia::Seguradoras::Universal::Codigos::INDISPONIVEL unless catalogo_com_planos?(catalogo)

      catalogo
    end
  end

  private

  def catalogo_com_planos?(catalogo)
    catalogo.is_a?(Hash) && catalogo['produtos'].is_a?(Array) && catalogo['produtos'].any?
  end

  # O carrinho vai no caminho: só um inteiro positivo, escrito só com dígitos. Outra coisa é recusada antes da chamada,
  # como pedido inválido, sem mensagem.
  def carrinho!(carrinho)
    texto = carrinho.to_s
    valido = !texto.empty? && texto.each_char.all? { |caractere| DIGITOS.cover?(caractere) } && texto.to_i.positive?
    raise Erro, Autonomia::Seguradoras::Universal::Codigos::PEDIDO_INVALIDO unless valido

    texto.to_i
  end

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
