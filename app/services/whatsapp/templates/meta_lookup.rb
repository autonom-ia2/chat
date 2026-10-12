# Asks Meta, right before a campaign goes out, for the current state of one template (#1329):
# one GET /{WABA}/message_templates?name=… with status, category and components. Returns the
# templates Meta answered (an Array, possibly empty when the template no longer exists) or nil when
# Meta could not be asked or did not answer (timeout, network error, non-2xx). The caller then
# falls back to the inbox cache (channel.message_templates). Nothing is written here.
#
# #1382: also asks for `id` and `parameter_format`, because the dispatch gate writes the approved
# item into the inbox list the send reads (Whatsapp::Templates::ChannelList), and the send needs
# `parameter_format` to build named variables. If Meta refuses a field (400, code 100) it asks
# again with the #1329 fields, as the sync does (Whatsapp::Templates::SyncFields).
class Whatsapp::Templates::MetaLookup
  FIELDS = 'id,name,language,status,category,parameter_format,components'.freeze
  BASE_FIELDS = 'name,language,status,category,components'.freeze
  INVALID_PARAMETER = 100
  TIMEOUT_SECONDS = 5
  PAGE_LIMIT = 100

  def initialize(channel:, name:)
    @channel = channel
    @name = name.to_s
  end

  def templates
    return unless askable?

    response = ask(FIELDS)
    response = ask(BASE_FIELDS) if field_refused?(response)
    return log_failure("http_#{response.code}") unless response.success?

    data = response.parsed_response.is_a?(Hash) ? response.parsed_response['data'] : nil
    data.is_a?(Array) ? data : log_failure('unexpected_body')
  rescue StandardError => e
    log_failure(e.class.name)
  end

  private

  def ask(fields)
    HTTParty.get(url, query: { name: @name, fields: fields, limit: PAGE_LIMIT },
                      headers: { 'Authorization' => "Bearer #{@channel.template_access_token}" }, timeout: TIMEOUT_SECONDS)
  end

  def field_refused?(response)
    return false unless response.code.to_i == 400

    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    error.is_a?(Hash) && error['code'].to_i == INVALID_PARAMETER
  end

  def askable?
    @name.present? && waba_id.present? && @channel.template_access_token.present?
  end

  def url
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')}/#{waba_id}/message_templates"
  end

  def waba_id
    @channel.provider_config.to_h['business_account_id']
  end

  def log_failure(reason)
    Rails.logger.warn "[WhatsappTemplates::MetaLookup] channel=#{@channel.id} lookup_failed=#{reason}"
    nil
  end
end
