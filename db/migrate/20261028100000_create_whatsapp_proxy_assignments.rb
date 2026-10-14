# Proxy da Webshare por número de WhatsApp não oficial (#1516). Regra: um IP por CONTA, até N números por IP
# (WHATSAPP_PROXY_MAX_NUMBERS_PER_IP), duas contas nunca no mesmo IP — garantido pelo Assigner sob trava e pelas
# validações do modelo. `pool` é o plano do IP: isp (Static Residential, sessões Híbridas) ou datacenter (WAHA comum).
# Usuário e senha do proxy NÃO moram aqui (só um HMAC para notar troca): vêm da API da Webshare na hora de configurar
# a sessão. `webshare_proxy_id` vazio = proxy posto à mão fora da Webshare, só reservado (o código não o troca).
class CreateWhatsappProxyAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_proxy_assignments do |t|
      t.string :session_name, null: false
      t.bigint :account_id, null: false
      t.string :pool, null: false
      t.string :webshare_proxy_id
      t.string :proxy_address, null: false
      t.integer :proxy_port, null: false
      t.datetime :assigned_at, null: false
      # HMAC (chave derivada do secret_key_base) de usuário:senha do último proxy aplicado no motor. Só serve para notar
      # que a Webshare trocou a credencial do mesmo IP; não permite recuperá-la.
      t.string :credential_digest
      t.timestamps
    end
    add_index :whatsapp_proxy_assignments, :session_name, unique: true
    add_index :whatsapp_proxy_assignments, :proxy_address
    add_index :whatsapp_proxy_assignments, [:account_id, :pool]
  end
end
