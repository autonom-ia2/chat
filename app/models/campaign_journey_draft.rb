# Rascunho da "Nova campanha" guardado no servidor (#1898): quem só monta a campanha deixa ela pronta para disparar, e
# quem dispara abre pela lista. `payload` são as escolhas da jornada no formato do campaignDraft.js (canal, público,
# caixa, modelo, texto, quando), nunca dado de contato. `channel` usa os nomes da tela (CAMPAIGN_CHANNELS).
# No e-mail, a jornada já cria a EmailCampaign em rascunho; o rascunho guarda o id dela e sai quando ela é enviada.
class CampaignJourneyDraft < ApplicationRecord
  CHANNELS = %w[email whatsapp_official whatsapp_api sms].freeze
  MAX_PAYLOAD_BYTES = 64.kilobytes

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :email_campaign, optional: true

  validates :title, length: { maximum: 255 }
  validates :channel, inclusion: { in: CHANNELS }, allow_blank: true
  validate :payload_is_an_object
  validate :email_campaign_in_the_same_account

  # O e-mail que já saiu de rascunho (enviado, agendado) não está mais "pronto para disparar".
  scope :pending, lambda {
    joined = left_joins(:email_campaign)
    joined.where(email_campaign_id: nil).or(joined.where(email_campaigns: { status: EmailCampaign.statuses[:draft] }))
  }

  private

  def payload_is_an_object
    return errors.add(:payload, :invalid) unless payload.is_a?(Hash)

    errors.add(:payload, :too_long, count: MAX_PAYLOAD_BYTES) if payload.to_json.bytesize > MAX_PAYLOAD_BYTES
  end

  def email_campaign_in_the_same_account
    return if email_campaign_id.blank?
    return if email_campaign.present? && email_campaign.account_id == account_id

    errors.add(:email_campaign, :invalid)
  end
end
