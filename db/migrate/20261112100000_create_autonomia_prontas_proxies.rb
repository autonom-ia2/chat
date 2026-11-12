# Ferramentas prontas (#2942, parte do #2858): o IP próprio da Webshare de cada conta para as consultas grátis.
# - `autonomia_prontas_proxies`: o IP de cada conta (uma linha por conta; um IP é de uma conta só). Só endereço, porta e
#   o id do proxy na Webshare: a credencial vem da API na hora e nunca é gravada.
# - `autonomia_prontas_proxy_quarantines`: o IP que levou 429/403 repetidos de um host fica de molho por um tempo e não
#   é oferecido a nenhuma conta. Separada da quarentena do WhatsApp (`whatsapp_proxy_quarantines`, #1516).
# Só aditiva: duas tabelas novas, lidas só com a flag `agente_ferramentas_prontas_ip_proprio`. O down remove as duas.
class CreateAutonomiaProntasProxies < ActiveRecord::Migration[7.2]
  def change
    create_table :autonomia_prontas_proxies do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :proxy_address, null: false
      t.integer :proxy_port, null: false
      t.string :webshare_proxy_id
      t.datetime :assigned_at, null: false
      t.timestamps
    end
    add_index :autonomia_prontas_proxies, :proxy_address, unique: true

    create_table :autonomia_prontas_proxy_quarantines do |t|
      t.string :proxy_address, null: false, index: { unique: true }
      t.datetime :quarantined_until, null: false
      t.string :reason, null: false
      t.timestamps
    end
  end
end
