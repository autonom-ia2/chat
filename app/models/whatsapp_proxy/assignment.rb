# IP da Webshare de uma sessão do motor de WhatsApp não oficial (#1516). Um IP pertence a uma conta só e leva até
# WHATSAPP_PROXY_MAX_NUMBERS_PER_IP números dela. Só endereço e porta: a credencial vem da API na hora de configurar a
# sessão e nunca é gravada.
class WhatsappProxy::Assignment < ApplicationRecord
  self.table_name = 'whatsapp_proxy_assignments'

  POOLS = %w[isp datacenter].freeze
  DEFAULT_MAX_NUMBERS_PER_IP = 3

  validates :session_name, presence: true, uniqueness: true
  validates :account_id, presence: true
  validates :pool, inclusion: { in: POOLS }
  validates :proxy_address, presence: true
  validates :proxy_port, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :assigned_at, presence: true
  validate :one_account_per_ip
  validate :numbers_per_ip_within_limit

  def self.max_numbers_per_ip
    value = ENV.fetch('WHATSAPP_PROXY_MAX_NUMBERS_PER_IP', '').to_i
    value.positive? ? value : DEFAULT_MAX_NUMBERS_PER_IP
  end

  def self.sharing_ip(address, except_session:)
    where(proxy_address: address).where.not(session_name: except_session)
  end

  def server
    "#{proxy_address}:#{proxy_port}"
  end

  # Proxy posto à mão fora da Webshare: fica reservado, mas o código não tem a credencial para regravá-lo.
  def external?
    webshare_proxy_id.blank?
  end

  private

  def one_account_per_ip
    return unless self.class.sharing_ip(proxy_address, except_session: session_name).where.not(account_id: account_id).exists?

    errors.add(:proxy_address, 'já é de outra conta')
  end

  def numbers_per_ip_within_limit
    return if self.class.sharing_ip(proxy_address, except_session: session_name).count < self.class.max_numbers_per_ip

    errors.add(:proxy_address, "já tem #{self.class.max_numbers_per_ip} números")
  end
end
