# == Schema Information
#
# Table name: crm_meta_ads_connections
#
#  id                     :bigint           not null, primary key
#  access_token           :text
#  destinations           :jsonb            not null
#  insights_backfilled_at :datetime
#  insights_synced_at     :datetime
#  last_checked_at        :datetime
#  last_error             :string(255)
#  mode                   :string           default("token"), not null
#  pixel_name             :string(255)
#  status                 :string           default("active"), not null
#  verified_at            :datetime
#  ad_account_business_id :string
#  ad_account_id          :string
#  ad_account_name        :string(255)
#  pixel_id               :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#
# Indexes
#
#  idx_crm_meta_ads_connections_partner_ad_account  (ad_account_id) UNIQUE WHERE ((mode)::text = 'partner'::text)
#  index_crm_meta_ads_connections_on_account_id     (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
# Conexão da conta com os anúncios da Meta (#1034, #1047). Uma por conta.
#
# Dois modos:
# - `token`: o cliente colou um token próprio com ads_read (#1034). O token só existe cifrado; sem
#   ACTIVE_RECORD_ENCRYPTION_* o model recusa gravar.
# - `partner`: o cliente compartilhou a conta de anúncios com o portfólio da plataforma; a leitura usa o
#   token da plataforma (`Crm::MetaAds::Platform`). Não há token por conta.
#
# O token sai daqui apenas para o header Authorization do cliente da Graph; nunca para payload, log ou
# mensagem de erro (`public_payload` não o conhece).
class Crm::MetaAdsConnection < ApplicationRecord
  self.table_name = 'crm_meta_ads_connections'

  STATUSES = %w[active invalid].freeze
  MODES = %w[token partner].freeze
  DESTINATIONS = %w[whatsapp site].freeze
  LAST_ERROR_LIMIT = 255
  NAME_LIMIT = 255
  # No modo `partner` o erro é do token da plataforma: o cliente vê só um código, nunca a mensagem da Meta.
  PLATFORM_TOKEN_REJECTED = 'platform_token_rejected'.freeze
  # A Meta recusou ler a conta de anúncios escolhida: o cliente retirou o compartilhamento ou a chave perdeu o
  # acesso a ela (#1073, CA-2.6). A conta para de ser lida até ser conectada de novo.
  AD_ACCOUNT_ACCESS_LOST = 'ad_account_access_lost'.freeze

  encrypts :access_token

  belongs_to :account

  validates :access_token, presence: true, if: :token_mode?
  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }
  validates :account_id, uniqueness: true
  validates :ad_account_id, uniqueness: { conditions: -> { where(mode: 'partner') } }, allow_nil: true, if: :partner_mode?
  validate :access_token_requires_encryption

  scope :active, -> { where(status: 'active') }

  def self.active_for(account_id)
    active.find_by(account_id: account_id)
  end

  def self.public_payload_for(connection)
    return { configured: false, status: nil, mode: nil, last_checked_at: nil, last_error: nil } if connection.blank?

    connection.public_payload
  end

  def public_payload
    {
      configured: true, status: status, mode: mode, last_checked_at: last_checked_at, last_error: last_error,
      verified_at: verified_at, destinations: destinations_payload,
      ad_account: ad_account_id.present? ? { id: ad_account_id, name: ad_account_name } : nil,
      pixel: pixel_id.present? ? { id: pixel_id, name: pixel_name } : nil
    }
  end

  def token_mode?
    mode == 'token'
  end

  def partner_mode?
    mode == 'partner'
  end

  def active?
    status == 'active'
  end

  # Token usado para ler a Meta: o do cliente no modo `token`, o da plataforma no modo `partner`.
  def read_token
    partner_mode? ? Crm::MetaAds::Platform.token : access_token
  end

  # Pode ler a Meta agora? No modo `partner` o dono da conta de anúncios precisa continuar sendo um portfólio
  # do WhatsApp desta conta: se o número sai ou muda de portfólio, a leitura para (#1047).
  def readable?
    return access_token.present? if token_mode?

    Crm::MetaAds::Platform.token.present? && ad_account_id.present? &&
      Crm::MetaAds::Portfolios.for(account).include?(ad_account_business_id.to_s)
  end

  # Pode ler os insights da conta de anúncios escolhida agora (#1073)?
  def insights_readable?
    active? && ad_account_id.present? && readable?
  end

  def destinations_payload
    DESTINATIONS.index_with { |key| destinations.to_h[key] == true }
  end

  def mark_checked!
    update!(status: 'active', last_checked_at: Time.current, last_error: nil)
  end

  # A Meta recusou o token: a conta passa a "precisa atenção" e a resolução para até um novo token.
  # No modo `partner` o token é da plataforma, não do cliente: a conta guarda só um código e continua
  # ativa, porque trocar o token da plataforma resolve todas de uma vez.
  def mark_invalid!(message)
    return update!(last_error: PLATFORM_TOKEN_REJECTED) if partner_mode?

    update!(status: 'invalid', last_error: self.class.safe_error(message))
  end

  # Diferente de mark_invalid!, vale nos dois modos: o problema é desta conta de anúncios, não do token da
  # plataforma.
  def mark_access_lost!
    update!(status: 'invalid', last_error: AD_ACCOUNT_ACCESS_LOST)
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
