# Conexão auxiliar WhatsApp Web (WAHA) de uma caixa WhatsApp Oficial (Cloud) — chat#1067.
# A caixa Cloud continua dona da conversa; a sessão WAHA é só um segundo transporte de envio.
class WhatsappHybrid::Connection < ApplicationRecord
  self.table_name = 'whatsapp_hybrid_connections'

  ORIGINS = %w[human bot automation campaign].freeze
  STATUSES = %w[pending awaiting_scan connecting connected failed disconnected].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :risk_accepted_by, class_name: 'User', optional: true

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

  def origin_enabled?(origin)
    disabled_origins.exclude?(origin.to_s)
  end

  # Pronta para o roteador escolher o transporte Web.
  def routable?
    routing_enabled && risk_accepted? && status == 'connected' && same_number?
  end

  private

  def disabled_origins_are_known
    return if (Array(disabled_origins) - ORIGINS).empty?

    errors.add(:disabled_origins, :inclusion)
  end
end
