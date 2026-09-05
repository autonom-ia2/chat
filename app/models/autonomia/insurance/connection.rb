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
#  session_payload         :text
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
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
# Conexão da corretora com um provider de cotação (AGGER primeiro). Uma por conta e provider.
# A senha do portal só existe cifrada: sem ACTIVE_RECORD_ENCRYPTION_* configurado o model recusa
# gravar credencial — nunca texto puro no banco (PRD §14, regra 6 do Rodrigo).
class Autonomia::Insurance::Connection < ApplicationRecord
  self.table_name = 'autonomia_insurance_connections'

  PROVIDERS = %w[agger].freeze
  # Margem antes do vencimento em que a sessão já é considerada velha. Uma cotação leva até ~90s;
  # renovar com folga evita a sessão morrer no meio de um polling em andamento.
  SESSION_MARGIN = 5.minutes
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
  # A sessão aberta no portal. Cifrada pelo mesmo motivo da senha: não é a credencial da corretora,
  # mas é um portador que dá acesso ao portal enquanto vale.
  encrypts :session_payload

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

  # A sessão guardada, como o adapter a devolveu. Blob OPACO: guardamos e devolvemos, nunca
  # interpretamos — quem sabe o que tem dentro é o adapter.
  def session
    return if session_payload.blank?

    parsed = JSON.parse(session_payload)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  # Vale a pena reusar? Precisa existir E ter prazo com folga. Sem prazo informado pelo portal a
  # sessão NÃO é reusada: é melhor um login a mais do que uma cotação que morre no meio.
  def session_live?(now = Time.current)
    session.present? && session_expires_at.present? && session_expires_at > now + SESSION_MARGIN
  end

  def store_session!(payload, expires_at:, account_label: nil)
    update!(session_payload: payload.to_json, session_expires_at: expires_at,
            external_account_label: account_label.presence || external_account_label)
  end

  # Esquece a sessão. Usado quando o portal recusa o que guardamos — a próxima operação abre outra.
  def forget_session!
    update!(session_payload: nil, session_expires_at: nil)
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
      updated_at: updated_at,
      # Diagnostico estruturado (criterios 1.1, 1.2, 1.6 e 4.5). `last_error` continua sendo o texto
      # para humano; estes tres sao o que a tela DECIDE em cima -- que mensagem mostrar, se pede
      # acao do corretor, e o que ainda nao foi verificado.
      failure: last_failure,
      evidence: last_evidence,
      layers: layers,
      insurers_pending_auth: insurers_pending_auth
    }
  end

  # De quem e a acao nesta falha. Sem isso a tela so tem o `status`, e `auth_required` acabava
  # virando "confira sua senha" para qualquer 403 -- inclusive o de uma sessao que morreu.
  def last_failure
    metadata.to_h['last_failure'].presence
  end

  # O que foi verificado, quando e com que resultado (1.6).
  def last_evidence
    metadata.to_h['last_evidence'].presence
  end

  # As cinco camadas do 1.2. Ausente e diferente de `unknown`: ausente quer dizer que a conexao
  # nunca foi verificada por uma versao que sabe separa-las.
  def layers
    metadata.to_h['layers'].presence
  end

  # Seguradoras que recusaram a credencial que a corretora guardou NO PORTAL. Descoberto durante a
  # cotacao e trazido para ca porque e aqui que tem conserto -- nunca para o cliente final (4.5).
  def insurers_pending_auth
    metadata.to_h['insurers_pending_auth'].presence
  end

  # Registra o achado da cotacao SEM sobrescrever o resto de `metadata` (a comissao mora la).
  # Escreve so quando o conjunto muda: o polling passa aqui de poucos em poucos segundos.
  def record_insurers_pending_auth!(codigos, nomes:, observed_at: Time.current)
    atual = insurers_pending_auth
    novo = { 'codes' => codigos.sort, 'names' => nomes, 'observed_at' => observed_at.iso8601 }
    return if atual.is_a?(Hash) && atual['codes'] == novo['codes']

    update!(metadata: metadata.to_h.merge('insurers_pending_auth' => codigos.empty? ? nil : novo))
  end

  private

  def credentials_require_encryption
    return if password.blank? && username.blank? && session_payload.blank?
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
