# Conexão auxiliar WhatsApp Web (WAHA) de uma caixa WhatsApp Oficial (Cloud) — chat#1067.
# A caixa Cloud continua dona da conversa; a sessão WAHA é só um segundo transporte de envio.
class WhatsappHybrid::Connection < ApplicationRecord
  self.table_name = 'whatsapp_hybrid_connections'

  ORIGINS = %w[human bot automation campaign].freeze
  STATUSES = %w[pending awaiting_scan connecting connected failed disconnected].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :risk_accepted_by, class_name: 'User', optional: true

  encrypts :webhook_secret if Chatwoot.encryption_configured?

  before_validation :assign_public_id, on: :create
  # Excluir a conexão (ou a caixa) desliga o aparelho no celular e apaga a sessão no motor.
  after_destroy_commit { WhatsappHybrid::TeardownSessionJob.perform_later(session_name) }

  validates :session_name, presence: true, uniqueness: true
  validates :inbox_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :rate_limit_per_minute, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 120 }
  validate :disabled_origins_are_known

  def risk_accepted?
    risk_accepted_at.present?
  end

  # O número conectado na sessão precisa ser o mesmo da caixa Cloud.
  def same_number?
    connected_phone.present? && connected_phone == cloud_phone_digits
  end

  def cloud_phone_digits
    inbox.channel.phone_number.to_s.delete('^0-9')
  end

  # Segredo do HMAC do webhook do motor; nasce na primeira configuração do webhook.
  def ensure_webhook_secret!
    update!(webhook_secret: SecureRandom.hex(32)) if webhook_secret.blank?
    webhook_secret
  end

  def webhook_url
    "#{Waha::Config.chatwoot_base_url}/webhooks/whatsapp_hybrid/#{public_id}"
  end

  def origin_enabled?(origin)
    disabled_origins.exclude?(origin.to_s)
  end

  # Pronta para o roteador escolher o transporte Web.
  def routable?
    routable_when_connected? && status == 'connected'
  end

  # Estava em uso pelo roteador (só essas quedas viram aviso ao administrador).
  def routable_when_connected?
    routing_enabled && risk_accepted? && same_number?
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def disabled_origins_are_known
    return if (Array(disabled_origins) - ORIGINS).empty?

    errors.add(:disabled_origins, :inclusion)
  end
end
