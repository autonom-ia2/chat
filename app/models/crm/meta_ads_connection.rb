# == Schema Information
#
# Table name: crm_meta_ads_connections
#
#  id              :bigint           not null, primary key
#  access_token    :text             not null
#  last_checked_at :datetime
#  last_error      :string(255)
#  status          :string           default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_crm_meta_ads_connections_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
# Credencial de leitura de anúncios da Meta (ads_read), uma por conta (#1034). Serve só para
# trocar os IDs dos parâmetros automáticos pelos nomes de campanha, conjunto e anúncio.
#
# O token só existe cifrado: sem ACTIVE_RECORD_ENCRYPTION_* o model recusa gravar (igual a
# AiProviderCredential). Ele sai daqui apenas para o header Authorization do cliente da Graph;
# nunca para payload, log ou mensagem de erro (`public_payload` não o conhece).
class Crm::MetaAdsConnection < ApplicationRecord
  self.table_name = 'crm_meta_ads_connections'

  STATUSES = %w[active invalid].freeze
  LAST_ERROR_LIMIT = 255

  encrypts :access_token

  belongs_to :account

  validates :access_token, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :account_id, uniqueness: true
  validate :access_token_requires_encryption

  scope :active, -> { where(status: 'active') }

  def self.active_for(account_id)
    active.find_by(account_id: account_id)
  end

  def self.public_payload_for(connection)
    return { configured: false, status: nil, last_checked_at: nil, last_error: nil } if connection.blank?

    connection.public_payload
  end

  def public_payload
    { configured: true, status: status, last_checked_at: last_checked_at, last_error: last_error }
  end

  def active?
    status == 'active'
  end

  def mark_checked!
    update!(status: 'active', last_checked_at: Time.current, last_error: nil)
  end

  # A Meta recusou o token: a conta passa a "precisa atenção" e a resolução para até um novo token.
  def mark_invalid!(message)
    update!(status: 'invalid', last_error: self.class.safe_error(message))
  end

  def self.safe_error(message)
    message.to_s.gsub(Meta::ConversionsApiClient::SENSITIVE_PATTERN, '<REDACTED>').first(LAST_ERROR_LIMIT).presence
  end

  private

  def access_token_requires_encryption
    return if access_token.blank? || Chatwoot.encryption_configured?

    errors.add(:base, 'ACTIVE_RECORD_ENCRYPTION must be configured before storing the Meta ads token')
  end
end
