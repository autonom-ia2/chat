# Transporte real: chama o serviço da máquina de adapters (repo autonom-ia2/autonomia-adapters),
# que é quem sabe falar com o AGGER. O chat2you não conhece endpoint, campo nem formato do portal.
#
# Caminho: API de invocação do Lambda (`lambda.<region>.amazonaws.com`), assinada com SigV4 pela
# credencial da própria instância. NÃO existe Function URL nem endpoint público — a política da
# organização bloqueia URL pública, e manter assim é o desenho correto: a única forma de chamar o
# serviço é ser a máquina do chat2you. `x-service-token` viaja dentro do evento como segunda camada.
class Autonomia::Insurance::Connector::Http < Autonomia::Insurance::Connector::Client
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60 # login no AGGER ~3 s; descoberta de produtos ~8 s; folga para cold start

  KIND_BY_STATUS = {
    400 => :protocol,
    401 => :auth_required,
    403 => :auth_required,
    404 => :protocol,
    405 => :protocol,
    422 => :validation,
    500 => :protocol,
    501 => :not_implemented,
    502 => :unavailable,
    503 => :unavailable,
    504 => :timeout
  }.freeze

  # ÚNICA operação que leva credencial. As demais viajam com a sessão que ela devolve — o portal
  # aceita uma sessão viva por login, e abrir outra invalida a anterior, inclusive a de uma cotação
  # em andamento.
  def open_session(provider:, username:, password:)
    invoke("/v1/#{provider}/session", { username: username, password: password })
  end

  def connection_status(provider:, session:)
    invoke("/v1/#{provider}/connection", { session: session })
  end

  def capabilities(provider:, session:)
    invoke("/v1/#{provider}/capabilities", { session: session })
  end

  def quote_start(provider:, session:, product:, input:)
    invoke("/v1/#{provider}/quote/start", { session: session, product: product, input: input })
  end

  def quote_result(provider:, session:, quote_id:)
    invoke("/v1/#{provider}/quote/result", { session: session, quoteId: quote_id })
  end

  def quote_proposal(provider:, session:, quote_id:, insurer_code: nil)
    payload = { session: session, quoteId: quote_id }
    payload[:insurerCode] = insurer_code if insurer_code.present?
    invoke("/v1/#{provider}/quote/proposal", payload)
  end

  private

  def invoke(path, payload)
    raise error(:config, 'INSURANCE_CONNECTOR_FUNCTION ausente') if function_name.blank?

    response = perform(build_event(path, payload))
    parse(response, path)
  rescue Autonomia::Insurance::Connector::Error
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise error(:timeout, "connector timeout em #{path}")
  rescue StandardError => e
    # Nunca repassar a mensagem: pode conter a requisição assinada (credencial temporária).
    raise error(:unavailable, "connector indisponível (#{e.class.name})")
  end

  # Evento no formato Function URL (payload v2) — o mesmo handler serve os dois caminhos.
  def build_event(path, payload)
    {
      rawPath: path,
      requestContext: { http: { method: 'POST', path: path } },
      headers: { 'x-service-token' => service_token }.compact,
      body: payload.to_json
    }.to_json
  end

  def perform(event)
    uri = invoke_uri
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['content-type'] = 'application/json'
    signed_headers(uri, event).each { |key, value| request[key] = value }
    request.body = event

    http.request(request)
  end

  def signed_headers(uri, body)
    Aws::Sigv4::Signer.new(
      service: 'lambda',
      region: region,
      credentials_provider: credentials_provider
    ).sign_request(
      http_method: 'POST',
      url: uri.to_s,
      headers: { 'content-type' => 'application/json' },
      body: body
    ).headers
  end

  def credentials_provider
    @credentials_provider ||= Aws::InstanceProfileCredentials.new
  end

  # FRONTEIRA ENTRE DOIS MUNDOS. O adapter é TypeScript e exporta camelCase — é a convenção de lá,
  # está no contrato (`core/adapter.ts`) e o CLI dele consome direto. Aqui é Ruby, e todo o resto do
  # namespace lê snake_case. A tradução mora nesta linha e em nenhum outro lugar.
  #
  # Isto NÃO era feito, e custou caro: `expiresAt` chegava e `payload['expires_at']` lia nil. Com
  # `session_expires_at` nulo, `session_live?` era SEMPRE falso — a sessão única nunca reusava nada,
  # cada chamada abria um login, e como o AGGER derruba a sessão anterior a cada login, a sessão que
  # acabáramos de mandar já estava morta quando o portal a recebia. O sintoma foi
  # `GET /cfg/corretora -> 403` e uma tela dizendo "credencial recusada" com a credencial válida.
  #
  # SÓ o primeiro nível é traduzido. `data` é a sessão opaca do portal — quem entende o que tem lá
  # dentro é o adapter, e mexer nas chaves dela quebraria o token na volta.
  CAMEL_TO_SNAKE = {
    'expiresAt' => 'expires_at',
    'sessionExpiresAt' => 'session_expires_at',
    'accountLabel' => 'account_label',
    'checkedAt' => 'checked_at',
    'scannedAt' => 'scanned_at',
    'droppedPreviousSession' => 'dropped_previous_session',
    # Camadas do critério 1.2. Chegam ANINHADAS em `layers`, e é por isso que a tradução deixou de
    # ser só do primeiro nível: uma camada lida como nil vira "não sei" quando na verdade era
    # "falhou", e o 1.2 existe exatamente para não confundir esses dois.
    'platformAuth' => 'platform_auth',
    'insurerAuth' => 'insurer_auth',
    'productSupport' => 'product_support',
    # Prêmio do critério 5.5: sem estas, o significado do valor se perde na fronteira e o Rails
    # volta a ter um número sem unidade.
    'basisEvidence' => 'basis_evidence'
  }.freeze

  # `data` é a sessão OPACA do portal: renomear chave lá dentro quebra o token na volta. É a única
  # exceção, e ela é do desenho, não um caso especial.
  OPACO = 'data'.freeze

  def normalize_keys(payload, raiz: true)
    return payload.map { |item| normalize_keys(item, raiz: false) } if payload.is_a?(Array)
    return payload unless payload.is_a?(Hash)

    payload.each_with_object({}) { |(key, value), out| put_normalized(out, key, value, raiz: raiz) }
  end

  def put_normalized(out, key, value, raiz:)
    snake = CAMEL_TO_SNAKE[key] || key
    # A chave em snake_case tem precedência: se o adapter um dia mandar as duas, a nossa vence.
    return if out[snake].present?

    # `data` é opaco SÓ na raiz, onde ele é a sessão do portal. Mais fundo, `data` é um nome comum
    # de campo, e tratar qualquer um deles como opaco pararia a tradução de um ramo inteiro sem
    # ninguém perceber.
    out[snake] = raiz && key == OPACO ? value : normalize_keys(value, raiz: false)
  end

  # A invocação devolve 200 com o retorno do handler no corpo; o status de negócio está em
  # `statusCode`. Erro de infraestrutura (permissão, função ausente) vem no HTTP externo.
  def parse(response, path)
    outer = unwrap_invocation(response)
    inner_code = outer['statusCode'].to_i
    payload = json_or_nil(outer['body'])

    return normalize_keys(payload) if inner_code == 200 && payload.is_a?(Hash)
    raise error(:protocol, "resposta inesperada do connector em #{path}") if inner_code == 200

    raise error(KIND_BY_STATUS.fetch(inner_code, :unavailable),
                business_message(payload) || "connector HTTP #{inner_code}")
  end

  # Camada de infraestrutura: a chamada foi aceita e o handler chegou a rodar?
  def unwrap_invocation(response)
    code = response.code.to_i
    raise error(KIND_BY_STATUS.fetch(code, :unavailable), "connector invoke HTTP #{code}") unless code == 200

    outer = json_or_nil(response.body)
    raise error(:unavailable, 'connector sem resposta') unless outer.is_a?(Hash)
    raise error(:unavailable, "connector falhou (#{outer['errorType']})") if outer['errorType'].present?

    outer
  end

  def business_message(payload)
    return nil unless payload.is_a?(Hash)

    (payload['message'].presence || payload['error'].presence).to_s.truncate(160).presence
  end

  def json_or_nil(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    nil
  end

  def error(kind, message)
    Autonomia::Insurance::Connector::Error.new(kind, message)
  end

  def invoke_uri
    URI("https://lambda.#{region}.amazonaws.com/2015-03-31/functions/#{function_name}/invocations")
  end

  def region
    @region ||= ENV.fetch('AWS_REGION', 'us-east-1')
  end

  def function_name
    @function_name ||= ENV.fetch('INSURANCE_CONNECTOR_FUNCTION', nil)
  end

  def service_token
    @service_token ||= ENV.fetch('INSURANCE_CONNECTOR_TOKEN', nil)
  end
end
