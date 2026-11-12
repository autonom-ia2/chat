# O IP da Webshare de uma conta para as consultas grátis das ferramentas prontas (#2942). Um IP é de uma conta só (índice
# único) e cada conta tem um. Só endereço, porta e o id na Webshare: a credencial vem da API na hora
# (`Saida::ListaDaWebshare`) e nunca é gravada. Quem escolhe e troca é a `Saida`, sempre sob `exclusivamente`.
class Autonomia::FerramentasProntas::ProxyDaConta < ApplicationRecord
  self.table_name = 'autonomia_prontas_proxies'

  # Trava própria, diferente da do WhatsApp (`WhatsappProxy::Assignment::LOCK_KEY`): as duas escolhas não se esperam.
  LOCK_KEY = 2_942_000_001

  belongs_to :account

  validates :account_id, uniqueness: true
  validates :proxy_address, presence: true, uniqueness: true
  validates :proxy_port, numericality: { only_integer: true, greater_than: 0 }
  validates :assigned_at, presence: true

  # Toda escolha de IP roda sob esta trava: duas contas nunca pegam o mesmo IP.
  def self.exclusivamente(&)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      yield
    end
  end

  def mesmo?(proxy)
    proxy.address == proxy_address && proxy.port == proxy_port
  end
end
