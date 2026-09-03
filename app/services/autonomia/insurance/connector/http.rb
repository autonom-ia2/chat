# Transporte real: chama o serviço da máquina de adapters (repo autonom-ia2/autonomia-adapters),
# que é quem sabe falar com o AGGER. O chat2you não conhece endpoint, campo nem formato do portal.
#
# Autenticação: a Function URL do Lambda exige AWS_IAM, então cada requisição é assinada (SigV4) com
# a credencial da própria instância — não existe endpoint público. `x-service-token` vai junto como
# segunda camada (defesa em profundidade).
class Autonomia::Insurance::Connector::Http < Autonomia::Insurance::Connector::Client
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 45 # login no AGGER ~3 s; descoberta de produtos ~8 s

  KIND_BY_STATUS = {
    400 => :protocol,
    401 => :auth_required,
    403 => :auth_required,
    404 => :protocol,
    422 => :validation,
    500 => :protocol,
    501 => :not_implemented,
    502 => :unavailable,
    503 => :unavailable,
    504 => :timeout
  }.freeze

  def connection_status(provider:, username:, password:)
    post("/v1/#{provider}/connection", username: username, password: password)
  end

  def capabilities(provider:, username:, password:)
    post("/v1/#{provider}/capabilities", username: username, password: password)
  end

  private

  def post(path, username:, password:)
    raise error(:config, 'INSURANCE_CONNECTOR_URL ausente') if base_url.blank?

    uri = URI.join(base_url, path.delete_prefix('/'))
    body = { username: username, password: password }.to_json
    parse(perform(uri, body), uri)
  rescue Autonomia::Insurance::Connector::Error
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise error(:timeout, "connector timeout em #{path}")
  rescue StandardError => e
    # Nunca repassar a mensagem: pode conter a URL assinada (credencial temporária).
    raise error(:unavailable, "connector indisponível (#{e.class.name})")
  end

  def perform(uri, body)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request['content-type'] = 'application/json'
    request['x-service-token'] = service_token if service_token.present?
    signed_headers(uri, body).each { |key, value| request[key] = value }
    request.body = body

    http.request(request)
  end

  # SigV4 com a credencial da instância (ou do ambiente, em dev). Sem isso a Function URL devolve 403.
  def signed_headers(uri, body)
    signature = Aws::Sigv4::Signer.new(
      service: 'lambda',
      region: ENV.fetch('AWS_REGION', 'us-east-1'),
      credentials_provider: credentials_provider
    ).sign_request(
      http_method: 'POST',
      url: uri.to_s,
      headers: { 'content-type' => 'application/json' },
      body: body
    )
    signature.headers
  end

  def credentials_provider
    @credentials_provider ||= Aws::InstanceProfileCredentials.new
  end

  def parse(response, uri)
    code = response.code.to_i
    payload = begin
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      nil
    end

    return payload if code == 200 && payload.is_a?(Hash)
    raise error(:protocol, "resposta não-JSON do connector em #{uri.path}") if code == 200

    message = payload.is_a?(Hash) ? (payload['message'].presence || payload['error'].presence) : nil
    raise error(KIND_BY_STATUS.fetch(code, :unavailable),
                message.to_s.truncate(160).presence || "connector HTTP #{code}")
  end

  def error(kind, message)
    Autonomia::Insurance::Connector::Error.new(kind, message)
  end

  def base_url
    @base_url ||= ENV.fetch('INSURANCE_CONNECTOR_URL', nil)
  end

  def service_token
    @service_token ||= ENV.fetch('INSURANCE_CONNECTOR_TOKEN', nil)
  end
end
