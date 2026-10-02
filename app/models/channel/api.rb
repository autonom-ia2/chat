# == Schema Information
#
# Table name: channel_api
#
#  id                    :bigint           not null, primary key
#  additional_attributes :jsonb
#  hmac_mandatory        :boolean          default(FALSE)
#  hmac_token            :string
#  identifier            :string
#  secret                :string
#  webhook_url           :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :integer          not null
#
# Indexes
#
#  index_channel_api_on_hmac_token  (hmac_token) UNIQUE
#  index_channel_api_on_identifier  (identifier) UNIQUE
#

class Channel::Api < ApplicationRecord
  include Channelable

  WHATSAPP_API_CAMPAIGN_CHANNEL_TYPE = 'whatsapp_api'.freeze
  WHATSAPP_API_CAMPAIGN_PROVIDER = 'waha'.freeze

  self.table_name = 'channel_api'
  EDITABLE_ATTRS = [:webhook_url, :hmac_mandatory, { additional_attributes: {} }].freeze

  has_secure_token :identifier
  has_secure_token :hmac_token
  include WebhookSecretable
  validate :ensure_valid_agent_reply_time_window
  validates :webhook_url, length: { maximum: Limits::URL_LENGTH_LIMIT }

  # Caixas provisionadas pelo conector WhatsApp API removem a sessão/app no motor
  # externo ao serem apagadas. Best-effort: nunca bloqueia a exclusão da caixa.
  before_destroy :cleanup_waha_remote, if: :waha_provider?

  def name
    'API'
  end

  def whatsapp_api_campaign_channel?
    channel_additional_attributes['campaign_channel_type'] == WHATSAPP_API_CAMPAIGN_CHANNEL_TYPE
  end

  def whatsapp_api_provider
    channel_additional_attributes['whatsapp_api_provider']
  end

  def enable_whatsapp_api_campaigns!(provider: WHATSAPP_API_CAMPAIGN_PROVIDER)
    update!(
      additional_attributes: channel_additional_attributes.merge(
        'campaign_channel_type' => WHATSAPP_API_CAMPAIGN_CHANNEL_TYPE,
        'whatsapp_api_provider' => provider
      )
    )
  end

  def disable_whatsapp_api_campaigns!
    attrs = channel_additional_attributes.except('campaign_channel_type', 'whatsapp_api_provider')
    update!(additional_attributes: attrs)
  end

  def waha_provider?
    channel_additional_attributes['provider'] == 'waha'
  end

  private

  def cleanup_waha_remote
    session = channel_additional_attributes['session']
    app_id = channel_additional_attributes['app_id']
    phone_numbers_app_id = channel_additional_attributes['phone_numbers_app_id']
    return true if session.blank?

    client = Waha::Client.new
    # Cada chamada isolada: falha ao remover um App NÃO impede remover os demais ou a sessão.
    safe_waha_call { client.delete_app(app_id) } if app_id.present?
    safe_waha_call { client.delete_app(phone_numbers_app_id) } if phone_numbers_app_id.present?
    safe_waha_call { client.delete_session(session) }
    true
  end

  def safe_waha_call
    yield
  rescue StandardError => e
    Rails.logger.warn("[Waha] cleanup on destroy failed for channel #{id}: #{e.class}")
    nil
  end

  def channel_additional_attributes
    (additional_attributes || {}).to_h
  end

  def ensure_valid_agent_reply_time_window
    return if channel_additional_attributes['agent_reply_time_window'].blank?
    return if channel_additional_attributes['agent_reply_time_window'].to_i.positive?

    errors.add(:agent_reply_time_window, 'agent_reply_time_window must be greater than 0')
  end
end
