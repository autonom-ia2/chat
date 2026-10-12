# Como o cliente de modelos (#1330) fala com a Graph API quando algo dá errado, no molde do
# `Crm::BookingV2::NoticeTemplates::Creator` (#1280): tenta de novo quando a Meta está fora do ar ou pede calma (5xx/429,
# pelo código HTTP), reconhece falta de permissão pelo código numérico da Meta e nunca devolve o token no texto.
# Incluído em `Whatsapp::Templates::MetaClient`; usa `@inbox` e `channel` dele.
module Whatsapp::Templates::GraphErrors
  MAX_ATTEMPTS = 3
  RETRY_DELAY = 0.5
  MAX_ERROR = 300
  PERMISSION_CODES = [10, 190].freeze
  PERMISSION_RANGE = (200..299)
  # 100/33: a Meta não diz qual dos dois: o objeto não existe (modelo apagado lá) ou este token não o alcança.
  NOT_FOUND_OR_NO_ACCESS = { code: 100, subcode: 33 }.freeze
  # Subcódigos de nome que a Meta devolve em inglês: viram texto nosso.
  NAME_SUBCODES = { 2_388_024 => 'name_taken', 2_388_023 => 'name_held' }.freeze
  NETWORK_ERRORS = (Crm::Ai::ResponsesClient::NETWORK_ERRORS + [HTTParty::Error]).freeze

  private

  # Repete o bloco quando a Meta está fora do ar, pede calma (5xx/429, pelo código HTTP) ou a rede cai.
  def with_retry
    attempt = 0
    begin
      attempt += 1
      yield
    rescue Whatsapp::Templates::MetaClient::Unreachable, *NETWORK_ERRORS => e
      Rails.logger.warn("[whatsapp][templates] meta_unreachable inbox_id=#{@inbox.id} attempt=#{attempt} error=#{e.class}")
      raise Whatsapp::Templates::MetaClient::Unreachable, e.class.name if attempt >= MAX_ATTEMPTS

      pause(attempt)
      retry
    end
  end

  def pause(attempt)
    sleep(RETRY_DELAY * attempt)
  end

  def retry_later!(response)
    code = response.code.to_i
    raise Whatsapp::Templates::MetaClient::Unreachable, "http_#{code}" if code >= 500 || code == 429
  end

  def fail_with(response)
    error = meta_error(response)
    own = own_text_code(error)
    raise Whatsapp::Templates::MetaClient::MetaError.new(text(own), own_text: true) if own

    message = error['error_user_msg'].presence || error['message'].presence
    raise Whatsapp::Templates::MetaClient::MetaError, without_token(message.to_s).first(MAX_ERROR)
  end

  # O erro que tem texto nosso (pelo código, nunca pela leitura do texto da Meta); nil quando vale o texto da Meta.
  def own_text_code(error)
    return 'permission_denied' if permission_error?(error)
    return 'not_found_or_no_access' if not_found_or_no_access?(error)
    return NAME_SUBCODES[error['error_subcode'].to_i] if NAME_SUBCODES.key?(error['error_subcode'].to_i)

    'meta_failed' if error['error_user_msg'].blank? && error['message'].blank?
  end

  # O erro da Graph API; no log só números (nada do texto, nada do token).
  def meta_error(response)
    error = payload(response)['error'].is_a?(Hash) ? payload(response)['error'] : {}
    Rails.logger.warn("[whatsapp][templates] meta_refused inbox_id=#{@inbox.id} http=#{response.code} " \
                      "code=#{error['code']} subcode=#{error['error_subcode']}")
    error
  end

  def payload(response)
    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  # Erro de permissão pelo código (10, 200–299) ou token inválido (190), nunca pela leitura do texto.
  def permission_error?(error)
    code = error['code'].to_i
    PERMISSION_CODES.include?(code) || PERMISSION_RANGE.cover?(code)
  end

  def not_found_or_no_access?(error)
    error['code'].to_i == NOT_FOUND_OR_NO_ACCESS[:code] && error['error_subcode'].to_i == NOT_FOUND_OR_NO_ACCESS[:subcode]
  end

  def without_token(text)
    token = channel.template_access_token.to_s
    token.empty? ? text : text.gsub(token, '[token]')
  end

  def text(key)
    I18n.t("whatsapp_templates.errors.#{key}", locale: account.locale.presence || I18n.default_locale)
  end
end
