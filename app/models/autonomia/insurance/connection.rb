# == Schema Information
#
# Table name: autonomia_insurance_connections
#
#  id                      :bigint           not null, primary key
#  capabilities            :jsonb            not null
#  capabilities_version    :string
#  external_account_label  :string
#  last_authenticated_at   :datetime
#  last_capability_scan_at :datetime
#  last_error              :string
#  last_healthcheck_at     :datetime
#  metadata                :jsonb            not null
#  password                :text
#  provider                :string           default("agger"), not null
#  session_expires_at      :datetime
#  status                  :string           default("not_configured"), not null
#  username                :text
#  username_hint           :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#
# Indexes
#
#  idx_autonomia_insurance_connections_account_provider  (account_id,provider) UNIQUE
#
# Conexão da corretora com um provider de cotação (AGGER primeiro). Uma por conta e provider.
# A senha do portal só existe cifrada: sem ACTIVE_RECORD_ENCRYPTION_* configurado o model recusa
# gravar credencial — nunca texto puro no banco (PRD §14, regra 6 do Rodrigo).
class Autonomia::Insurance::Connection < ApplicationRecord
  self.table_name = 'autonomia_insurance_connections'

  PROVIDERS = %w[agger].freeze
  # Estados do PRD §9.2. `auth_required` = o portal recusou a credencial da corretora;
  # `human_required` = precisa de alguém (reservado para MFA/CAPTCHA e falha que o adapter não resolve).
  # A tela e os textos precisam cobrir exatamente esta lista — insuranceStates.spec.js falha se divergir.
  STATUSES = %w[not_configured provisioning authenticating discovering ready degraded auth_required
                human_required offline].freeze

  belongs_to :account

  # Incondicional (diferente do padrão condicional do fork): sem chaves, a validação abaixo impede
  # qualquer escrita, então nunca existe linha em texto puro para o `encrypts` tropeçar.
  encrypts :username
  encrypts :password

  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :provider, uniqueness: { scope: :account_id }
  validate :credentials_require_encryption

  before_save :derive_username_hint

  scope :for_account, ->(account) { where(account: account) }

  def self.encryption_available?
    Chatwoot.encryption_configured?
  end

  def credentials_present?
    username.present? && password.present?
  end

  def ready?
    status == 'ready'
  end

  # O que sai para o frontend/logs. Senha e login completo NUNCA — só o hint mascarado.
  def public_payload
    {
      provider: provider,
      status: status,
      username_hint: username_hint,
      external_account_label: external_account_label,
      capabilities: capabilities,
      capabilities_version: capabilities_version,
      last_error: last_error,
      last_authenticated_at: last_authenticated_at,
      last_healthcheck_at: last_healthcheck_at,
      last_capability_scan_at: last_capability_scan_at,
      session_expires_at: session_expires_at,
      encryption_available: self.class.encryption_available?,
      updated_at: updated_at
    }
  end

  private

  def credentials_require_encryption
    return if password.blank? && username.blank?
    return if self.class.encryption_available?

    errors.add(:base, I18n.t('autonomia.insurance.errors.encryption_unavailable'))
  end

  def derive_username_hint
    return if username.blank?

    local, domain = username.split('@', 2)
    masked = "#{local.to_s[0, 2]}#{'*' * [local.to_s.length - 2, 2].max}"
    self.username_hint = domain ? "#{masked}@#{domain}" : masked
  end
end
