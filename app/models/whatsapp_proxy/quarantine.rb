# IP da Webshare que derrubou um número (sessão caindo e voltando no motor) fica fora da escolha por 24 h, para
# qualquer conta (#1516). No banco, e não no Redis, para a quarentena valer mesmo com o Redis fora. Expira sozinha
# (`quarantined_until`); à mão: `autonomia:whatsapp_proxy:liberar_quarentena[ip]`.
# Teto: no máximo DAILY_LIMIT IPs por plano em 24 h — acima disso o problema não é IP a IP, e quarentenar mais queimaria
# o plano inteiro.
class WhatsappProxy::Quarantine < ApplicationRecord
  self.table_name = 'whatsapp_proxy_quarantines'

  DURATION = 24.hours
  DAILY_LIMIT = 3

  validates :proxy_address, presence: true, uniqueness: true
  validates :pool, inclusion: { in: WhatsappProxy::Assignment::POOLS }
  validates :quarantined_until, :reason, presence: true

  scope :active, -> { where('quarantined_until > ?', Time.current) }

  # Ainda cabe quarentena neste plano hoje? Sem vaga, alerta (uma vez por hora) e responde false.
  def self.room?(pool)
    return true if where(pool: pool).where('updated_at > ?', DURATION.ago).count < DAILY_LIMIT

    WhatsappProxy::Alert.notify!('teto_de_quarentena', "plano #{pool} já teve #{DAILY_LIMIT} IPs em quarentena em 24 h",
                                 level: :error, pool: pool)
    false
  end

  def self.put!(address, pool, reason, notify: true)
    record = find_or_initialize_by(proxy_address: address)
    record.update!(pool: pool, quarantined_until: DURATION.from_now, reason: reason)
    notify_put(record) if notify
    record
  end

  def self.notify_put(record)
    WhatsappProxy::Alert.notify!('ip_em_quarentena', "IP #{record.proxy_address} (#{record.pool}) em quarentena por 24 h " \
                                                     "(#{record.reason})", ip: record.proxy_address, pool: record.pool)
  end

  # Quarentena provisória (sem alerta) e como desfazê-la: um registro que já existia volta ao estado de antes, um novo é
  # apagado.
  def self.provisional!(address, pool, reason)
    record = find_or_initialize_by(proxy_address: address)
    before = record.new_record? ? nil : record.attributes.slice('pool', 'quarantined_until', 'reason')
    record.update!(pool: pool, quarantined_until: DURATION.from_now, reason: reason)
    [record, before]
  end

  def undo!(before)
    before ? update!(before) : destroy!
  end

  def self.release!(address)
    where(proxy_address: address).delete_all
  end

  def self.addresses
    active.pluck(:proxy_address)
  end
end
