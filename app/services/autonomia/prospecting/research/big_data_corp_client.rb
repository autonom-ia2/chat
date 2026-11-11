require 'net/http'

# Cliente da BigDataCorp para a consulta de empresas (porte de lib/services/bigdatacorp/client.ts do Orth, #679). A F7 do
# #2858 (ferramentas Premium) usa o mesmo cliente em outras rotas (`query_route`), sem mudar a consulta de empresas.
#
# Fluxo: POST /tokens/gerar com BIGDATACORP_USER e BIGDATACORP_PASSWORD (só ENV, por Setting.platform_config) e depois
# POST /empresas com AccessToken e TokenId. O token fica em memória desta instância por TOKEN_TTL.
#
# Tentativas, como no Orth: o token repete em timeout, 429 e 5xx (BigDataCorpTokenIssuer). A consulta paga repete só em
# 429 e 5xx explícitos e gera token de novo uma única vez depois de um 401. Timeout ou falha de rede depois do envio
# NUNCA repete: a consulta pode ter chegado e sido cobrada. Fora do porte, por decisão do Rodrigo: cercas financeiras,
# custo e retomada durável. Redirecionamento não é seguido (Net::HTTP não segue; 3xx vira BIGDATACORP_HTTP_ERROR).
#
# Credencial e token nunca saem daqui: não vão para mensagem de erro, log nem inspect. O erro leva só código fechado,
# fase, status HTTP e número de tentativas.
#
# Opções da F7 do #2858 (as ferramentas Premium), todas desligadas no padrão (a Prospecção segue igual):
#   - `token_timeout`: o prazo do pedido de token; nil usa o `timeout`;
#   - `token_cache`: onde guardar o token entre instâncias (`read`, `write` e `forget(token)`, que só apaga se o
#     guardado ainda for aquele); nil guarda só nesta instância;
#   - `resend_after_unauthorized`: depois de um 401, um reenvio com token novo mesmo na última tentativa (a BigDataCorp
#     não cobra o 401). Desligado, o 401 da última tentativa levanta, como antes.
# Todo 401 apaga o token recusado (desta instância e do `token_cache`): a consulta seguinte gera outro.
class Autonomia::Prospecting::Research::BigDataCorpClient
  BASE_URI = URI('https://plataforma.bigdatacorp.com.br').freeze
  COMPANIES_PATH = '/empresas'.freeze
  ROUTES = [COMPANIES_PATH, '/pessoas', '/veiculos', '/enderecos', '/ondemand', '/marketplace'].freeze
  USER_ENV = 'BIGDATACORP_USER'.freeze
  PASSWORD_ENV = 'BIGDATACORP_PASSWORD'.freeze
  RETRY_BASE_DELAY_SECONDS = 0.25
  MAX_REQUEST_ID_LENGTH = 160
  NETWORK_ERRORS = [SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError].freeze
  LOG_TAG = '[Prospecting::Research::BigDataCorpClient]'.freeze
  DEFAULTS = {
    sleeper: ->(seconds) { sleep(seconds) },
    clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
    token_ttl: 10.minutes.to_i,
    timeout: 20,
    max_provider_attempts: 3,
    max_token_attempts: 3,
    token_timeout: nil,
    token_cache: nil,
    resend_after_unauthorized: false
  }.freeze

  # Segredo que não aparece em inspect, to_s nem pretty print.
  module Redacted
    def inspect = "#<#{self.class.name} [REDACTED]>"
    def to_s = inspect
    def pretty_print(printer) = printer.text(inspect)
  end

  Credentials = Struct.new(:username, :password, keyword_init: true) { include Redacted }
  Token = Struct.new(:access_token, :token_id, :expires_at, keyword_init: true) { include Redacted }
  Response = Struct.new(:payload, :metadata, keyword_init: true)

  class Error < StandardError
    attr_reader :code, :phase, :status, :provider_attempts

    def initialize(code, phase:, status: nil, provider_attempts: 0)
      @code = code
      @phase = phase
      @status = status
      @provider_attempts = provider_attempts
      super(code)
    end
  end

  def self.configured?
    platform_credentials.all?(&:present?)
  end

  def self.platform_credentials
    [USER_ENV, PASSWORD_ENV].map { |name| Autonomia::Prospecting::Setting.platform_config(name)&.strip }
  end

  # credentials: { username:, password: } só em teste; em produção fica nil e a leitura é do ENV, na hora do token.
  # options: as chaves de DEFAULTS e logger.
  def initialize(credentials: nil, **options)
    @credentials = credentials && Credentials.new(username: credentials[:username].to_s.strip, password: credentials[:password].to_s.strip)
    @options = DEFAULTS.merge(options.slice(*DEFAULTS.keys))
    @logger = options.fetch(:logger) { Rails.logger }
    @token = nil
    @issuer = Autonomia::Prospecting::Research::BigDataCorpTokenIssuer.new(
      transport: self, max_attempts: @options[:max_token_attempts], ttl: @options[:token_ttl]
    )
  end

  def inspect = "#<#{self.class.name} [REDACTED]>"
  alias to_s inspect

  # Devolve Response(payload: Hash, metadata: { provider_attempts:, token_generations:, provider_request_id: }).
  # Levanta Error com código fechado.
  def search_companies(query:, limit: 3, datasets: 'basic_data')
    query_route(COMPANIES_PATH, query: query, datasets: datasets, limit: limit)
  end

  # #2858 F7: a mesma consulta paga em outra rota da plataforma (as ferramentas Premium da vitrine). Só as rotas de
  # `ROUTES`; o resto (token, retentativa, erros, segredo fora de log) é o mesmo da consulta de empresas.
  def query_route(path, query:, datasets:, limit: 1)
    raise ArgumentError, 'rota da BigDataCorp fora da lista' unless ROUTES.include?(path)

    @token_generations = 0
    dispatch_with_retries(path, { Datasets: datasets, q: query, Limit: limit }.to_json)
  end

  # Transporte, usado também pelo BigDataCorpTokenIssuer.
  def post(path, body, headers)
    http = Net::HTTP.new(BASE_URI.host, BASE_URI.port)
    http.use_ssl = true
    timeout = timeout_for(path)
    %i[open_timeout= read_timeout= write_timeout= ssl_timeout=].each { |setter| http.public_send(setter, timeout) }
    http.max_retries = 0
    request = Net::HTTP::Post.new(path, { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }.merge(headers))
    request.body = body
    http.request(request)
  end

  def timeout_for(path)
    return @options[:timeout] unless path == Autonomia::Prospecting::Research::BigDataCorpTokenIssuer::PATH

    @options[:token_timeout] || @options[:timeout]
  end

  def retryable?(status)
    status == 429 || status >= 500
  end

  def pause(attempt)
    @options[:sleeper].call(RETRY_BASE_DELAY_SECONDS * (2**(attempt - 1)))
  end

  def now
    @options[:clock].call
  end

  def parse_json(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    nil
  end

  # Só evento, fase, tentativa, status e código. Nada de corpo, credencial ou token.
  def log(event, phase, attempt, status, code)
    @logger.warn("#{LOG_TAG} event=#{event} phase=#{phase} attempt=#{attempt} status=#{status || '-'} code=#{code}")
  end

  private

  def dispatch_with_retries(path, body)
    state = { attempts: 0, refreshed: false, force_refresh: false, extra: 0 }
    while state[:attempts] < @options[:max_provider_attempts] + state[:extra]
      credential = provider_credential(state)
      state[:attempts] += 1
      outcome = classify(post_query(path, body, credential, state[:attempts]), state)
      return outcome if outcome
    end
    raise Error.new('BIGDATACORP_PROVIDER_UNAVAILABLE', phase: :provider, provider_attempts: state[:attempts])
  end

  # O erro de token antes do primeiro envio sai como está; depois de um envio, leva as tentativas já feitas.
  def provider_credential(state)
    credential = current_token(force_refresh: state[:force_refresh])
    state[:force_refresh] = false
    credential
  rescue Error => e
    raise if state[:attempts].zero?

    raise Error.new(e.code, phase: e.phase, status: e.status, provider_attempts: state[:attempts])
  end

  # Devolve Response, nil para tentar de novo, ou levanta.
  def classify(response, state)
    status = response.code.to_i
    attempts = state[:attempts]
    return unauthorized(state) if status == 401
    return wait_and_retry(status, attempts) if retryable?(status) && attempts < @options[:max_provider_attempts]
    raise failure('BIGDATACORP_HTTP_ERROR', status, attempts) unless status.between?(200, 299)

    payload = parse_json(response.body)
    raise failure('BIGDATACORP_DELIVERY_UNKNOWN', status, attempts) unless payload.is_a?(Hash)

    Response.new(payload: payload, metadata: metadata(payload, attempts))
  end

  # O primeiro 401 gera token novo e tenta de novo; o segundo levanta. Os dois apagam o token recusado.
  def unauthorized(state)
    return refresh_after_unauthorized(state) unless state[:refreshed]

    forget_token
    raise failure('BIGDATACORP_HTTP_ERROR', 401, state[:attempts])
  end

  def refresh_after_unauthorized(state)
    forget_token
    if state[:attempts] >= @options[:max_provider_attempts]
      raise failure('BIGDATACORP_HTTP_ERROR', 401, state[:attempts]) unless @options[:resend_after_unauthorized]

      state[:extra] = 1
    end
    state[:refreshed] = true
    state[:force_refresh] = true
    nil
  end

  def forget_token
    recusado = @token
    @token = nil
    @options[:token_cache]&.forget(recusado)
  end

  def wait_and_retry(status, attempts)
    log('provider_retry', :provider, attempts, status, 'BIGDATACORP_PROVIDER_RETRYABLE_HTTP')
    pause(attempts)
    nil
  end

  def failure(code, status, attempts)
    log('request_failed', :provider, attempts, status, code)
    Error.new(code, phase: :provider, status: status, provider_attempts: attempts)
  end

  def post_query(path, body, token, attempts)
    post(path, body, { 'AccessToken' => token.access_token, 'TokenId' => token.token_id })
  rescue Timeout::Error
    raise failure('BIGDATACORP_TIMEOUT', nil, attempts)
  rescue *NETWORK_ERRORS
    raise failure('BIGDATACORP_DELIVERY_UNKNOWN', nil, attempts)
  end

  def current_token(force_refresh: false)
    @token = force_refresh ? nil : @token || @options[:token_cache]&.read
    return @token if @token && @token.expires_at > now

    issue_token
  end

  def issue_token
    credentials = resolved_credentials
    @token_generations += 1
    @token = @issuer.issue(credentials)
    @options[:token_cache]&.write(@token)
    @token
  end

  def resolved_credentials
    credentials = @credentials || Credentials.new(username: self.class.platform_credentials.first, password: self.class.platform_credentials.last)
    raise Error.new('BIGDATACORP_NOT_CONFIGURED', phase: :configuration) if credentials.username.blank? || credentials.password.blank?

    credentials
  end

  def metadata(payload, attempts)
    request_id = payload['QueryId'].is_a?(String) ? payload['QueryId'].strip.presence&.first(MAX_REQUEST_ID_LENGTH) : nil
    { provider_attempts: attempts, token_generations: @token_generations, provider_request_id: request_id }
  end
end
