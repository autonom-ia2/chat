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
  # 100/33: o objeto existe, mas este token não o alcança (WABA ou modelo de outra conta, permissão tirada).
  NO_ACCESS = { code: 100, subcode: 33 }.freeze
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
    raise Whatsapp::Templates::MetaClient::MetaError.new(text('permission_denied'), own_text: true) if permission_error?(error)

    message = error['error_user_msg'].presence || error['message'].presence
    raise Whatsapp::Templates::MetaClient::MetaError.new(text('meta_failed'), own_text: true) if message.blank?

    raise Whatsapp::Templates::MetaClient::MetaError, without_token(message.to_s).first(MAX_ERROR)
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

  # Erro de permissão pelo código (10, 200–299, 100/33) ou token inválido (190), nunca pela leitura do texto.
  def permission_error?(error)
    code = error['code'].to_i
    return true if code == NO_ACCESS[:code] && error['error_subcode'].to_i == NO_ACCESS[:subcode]

    PERMISSION_CODES.include?(code) || PERMISSION_RANGE.cover?(code)
  end

  def without_token(text)
    token = channel.template_access_token.to_s
    token.empty? ? text : text.gsub(token, '[token]')
  end

  def text(key)
    I18n.t("whatsapp_templates.errors.#{key}", locale: account.locale.presence || I18n.default_locale)
  end
end
