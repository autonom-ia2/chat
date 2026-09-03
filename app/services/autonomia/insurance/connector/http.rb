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

  def connection_status(provider:, username:, password:)
    invoke("/v1/#{provider}/connection", username: username, password: password)
  end

  def capabilities(provider:, username:, password:)
    invoke("/v1/#{provider}/capabilities", username: username, password: password)
  end

  private

  def invoke(path, username:, password:)
    raise error(:config, 'INSURANCE_CONNECTOR_FUNCTION ausente') if function_name.blank?

    response = perform(build_event(path, username, password))
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
  def build_event(path, username, password)
    {
      rawPath: path,
      requestContext: { http: { method: 'POST', path: path } },
      headers: { 'x-service-token' => service_token }.compact,
      body: { username: username, password: password }.to_json
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

  # A invocação devolve 200 com o retorno do handler no corpo; o status de negócio está em
  # `statusCode`. Erro de infraestrutura (permissão, função ausente) vem no HTTP externo.
  def parse(response, path)
    outer = unwrap_invocation(response)
    inner_code = outer['statusCode'].to_i
    payload = json_or_nil(outer['body'])

    return payload if inner_code == 200 && payload.is_a?(Hash)
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
