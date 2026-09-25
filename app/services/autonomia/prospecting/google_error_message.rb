# Erro do Google Places em frase nossa, em português (#677). A chave é da plataforma (#683): o texto do Google fala do
# nosso projeto no Google Cloud, então ele vai só para o log do servidor. A escolha da frase lê campos estruturados da
# resposta (error.status e o reason de ErrorInfo), nunca o texto da mensagem.
module Autonomia::Prospecting::GoogleErrorMessage
  KEY_SCOPE = 'autonomia.prospecting.errors'.freeze
  UNAVAILABLE = 'google_unavailable'.freeze
  BUSY = 'google_busy'.freeze
  TIMEOUT = 'google_timeout'.freeze

  STATUS_KEYS = {
    'PERMISSION_DENIED' => UNAVAILABLE,
    'UNAUTHENTICATED' => UNAVAILABLE,
    'FAILED_PRECONDITION' => UNAVAILABLE,
    'RESOURCE_EXHAUSTED' => BUSY,
    'INVALID_ARGUMENT' => 'google_invalid_argument',
    'NOT_FOUND' => 'google_place_not_found',
    'UNAVAILABLE' => TIMEOUT,
    'DEADLINE_EXCEEDED' => TIMEOUT,
    'INTERNAL' => TIMEOUT
  }.freeze

  # Sem error.status no corpo, vale o código HTTP.
  HTTP_KEYS = {
    429 => BUSY,
    404 => 'google_place_not_found',
    500 => TIMEOUT,
    503 => TIMEOUT,
    504 => TIMEOUT
  }.freeze

  # O Google responde chave vencida ou API desligada como INVALID_ARGUMENT ou PERMISSION_DENIED. Nenhum dos dois é culpa
  # de quem busca.
  CONFIGURATION_REASONS = %w[API_KEY_INVALID API_KEY_EXPIRED API_KEY_SERVICE_BLOCKED SERVICE_DISABLED].freeze

  # Timeout::Error cobre Net::OpenTimeout e Net::ReadTimeout. Classe fora daqui escapa crua e vira 500 em inglês.
  NETWORK_ERRORS = [
    HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
    Errno::EHOSTUNREACH, Errno::ENETUNREACH, OpenSSL::SSL::SSLError
  ].freeze

  module_function

  # code: código HTTP; body: corpo da resposta; context: quem chamou, para o log.
  def for_response(code:, body:, context:, account_id:)
    error = parsed_error(body)
    Rails.logger.warn(
      "[Prospecting::GooglePlaces] #{context} account_id=#{account_id} status=#{code} " \
      "google_status=#{error['status'].presence || 'sem status'} google_message=#{error['message'].presence || 'sem mensagem'}"
    )
    I18n.t(key_for(code.to_i, error), scope: KEY_SCOPE)
  end

  def for_exception(exception, context:, account_id:)
    Rails.logger.warn("[Prospecting::GooglePlaces] #{context} account_id=#{account_id} error=#{exception.class.name}: #{exception.message}")
    key = NETWORK_ERRORS.any? { |klass| exception.is_a?(klass) } ? TIMEOUT : UNAVAILABLE
    I18n.t(key, scope: KEY_SCOPE)
  end

  def key_for(code, error)
    return UNAVAILABLE if configuration_problem?(error)

    STATUS_KEYS[error['status']] || HTTP_KEYS[code] || UNAVAILABLE
  end

  def configuration_problem?(error)
    Array(error['details']).any? { |detail| CONFIGURATION_REASONS.include?(detail.to_h['reason']) }
  end

  def parsed_error(body)
    parsed = JSON.parse(body.to_s)
    parsed.is_a?(Hash) ? parsed['error'].to_h : {}
  rescue JSON::ParserError
    {}
  end
end
