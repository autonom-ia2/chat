# IP da Webshare que derrubou um número (sessão caindo e voltando no motor) fica fora da escolha por 24 h, para
# qualquer conta (#1516). No banco, e não no Redis, para a quarentena valer mesmo com o Redis fora.
class WhatsappProxy::Quarantine < ApplicationRecord
  self.table_name = 'whatsapp_proxy_quarantines'

  DURATION = 24.hours

  validates :proxy_address, presence: true, uniqueness: true
  validates :quarantined_until, :reason, presence: true

  scope :active, -> { where('quarantined_until > ?', Time.current) }

  def self.put!(address, reason)
    record = find_or_initialize_by(proxy_address: address)
    record.update!(quarantined_until: DURATION.from_now, reason: reason)
    WhatsappProxy::Alert.notify!('ip_em_quarentena', "IP #{address} em quarentena por 24 h (#{reason})")
    record
  end

  def self.addresses
    active.pluck(:proxy_address)
  end
end
