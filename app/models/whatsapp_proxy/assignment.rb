# IP da Webshare reservado para uma sessão do motor de WhatsApp não oficial (#1516). Só endereço e porta: a credencial
# vem da API na hora de configurar a sessão e nunca é gravada.
class WhatsappProxy::Assignment < ApplicationRecord
  self.table_name = 'whatsapp_proxy_assignments'

  validates :session_name, presence: true, uniqueness: true
  validates :proxy_address, presence: true, uniqueness: true
  validates :proxy_port, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :assigned_at, presence: true

  def server
    "#{proxy_address}:#{proxy_port}"
  end

  # Proxy posto à mão fora da Webshare: fica reservado, mas o código não tem a credencial para regravá-lo.
  def external?
    webshare_proxy_id.blank?
  end
end
