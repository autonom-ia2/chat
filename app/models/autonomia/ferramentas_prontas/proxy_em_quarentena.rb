# IP das consultas grátis que levou 429/403 repetidos de um host (`Saida::Recusas`): fica fora da escolha por DURACAO,
# para qualquer conta, e a conta dele ganha outro na próxima consulta (#2942). No banco, e não no Redis, para valer mesmo
# com o Redis fora. Expira sozinha (`quarantined_until`). Separada da quarentena do WhatsApp (#1516).
# Teto: no máximo TETO_DIARIO IPs em 24 h. Acima disso o problema não é IP a IP (a fonte bloqueou a Webshare inteira, ou o
# teto está alto), e pôr mais de molho só esvaziaria a fatia.
class Autonomia::FerramentasProntas::ProxyEmQuarentena < ApplicationRecord
  self.table_name = 'autonomia_prontas_proxy_quarantines'

  DURACAO = 6.hours
  TETO_DIARIO = 5

  validates :proxy_address, presence: true, uniqueness: true
  validates :quarantined_until, :reason, presence: true

  scope :ativas, -> { where('quarantined_until > ?', Time.current) }

  def self.enderecos
    ativas.pluck(:proxy_address)
  end

  def self.ativa?(endereco)
    ativas.exists?(proxy_address: endereco)
  end

  # Ainda cabe uma quarentena nas últimas 24 h?
  def self.cabe?
    where('updated_at > ?', 24.hours.ago).count < TETO_DIARIO
  end

  def self.por!(endereco, motivo)
    find_or_initialize_by(proxy_address: endereco).tap do |registro|
      registro.update!(quarantined_until: DURACAO.from_now, reason: motivo)
    end
  end
end
