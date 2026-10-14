# Proxy da Webshare por número de WhatsApp não oficial (#1516). Regra: um IP por CONTA, até N números por IP
# (WHATSAPP_PROXY_MAX_NUMBERS_PER_IP), duas contas nunca no mesmo IP — garantido pelo Assigner sob trava e pelas
# validações do modelo. `pool` é o plano do IP: isp (Static Residential, sessões Híbridas) ou datacenter (WAHA comum).
# Usuário e senha do proxy NÃO moram aqui (só um HMAC para notar troca): vêm da API da Webshare na hora de configurar
# a sessão. `webshare_proxy_id` vazio = proxy posto à mão fora da Webshare, só reservado (o código não o troca).
# `origin`: imported (proxy posto à mão antes do código, importado pela rake) ou assigned (escolhido pelo código).
# Endereço vazio = pendente: a caixa nasceu sem proxy (Webshare fora) e a reconciliação tenta de novo.
# `previous_*`: o estado de antes da última troca (IP, plano, conta, origem), para voltar a ele se o motor recusar.
# `apply_failures`/`last_apply_failed_at`: trocas desfeitas seguidas, para o recuo exponencial.
class CreateWhatsappProxyAssignments < ActiveRecord::Migration[7.2]
  def change
    create_assignments
    create_quarantines
  end

  private

  def create_assignments
    create_table :whatsapp_proxy_assignments do |t|
      t.string :session_name, null: false
      t.bigint :account_id, null: false
      t.string :pool, null: false
      t.string :webshare_proxy_id
      t.string :proxy_address
      t.integer :proxy_port
      t.datetime :assigned_at, null: false
      # HMAC (chave derivada do secret_key_base) de usuário:senha do último proxy aplicado no motor. Só serve para notar
      # que a Webshare trocou a credencial do mesmo IP; não permite recuperá-la.
      t.string :credential_digest
      t.string :origin, null: false, default: 'assigned'
      previous_columns(t)
      t.integer :apply_failures, null: false, default: 0
      t.datetime :last_apply_failed_at
      t.timestamps
    end
    index_assignments
  end

  def previous_columns(table)
    table.string :previous_proxy_address
    table.integer :previous_proxy_port
    table.string :previous_webshare_proxy_id
    table.string :previous_credential_digest
    table.string :previous_pool
    table.bigint :previous_account_id
    table.string :previous_origin
  end

  def index_assignments
    add_index :whatsapp_proxy_assignments, :session_name, unique: true
    add_index :whatsapp_proxy_assignments, :proxy_address
    add_index :whatsapp_proxy_assignments, [:account_id, :pool]
    add_foreign_key :whatsapp_proxy_assignments, :accounts, on_delete: :cascade
  end

  # IP que derrubou um número (sessão caindo e voltando) fica 24 h fora da escolha, para ninguém. `pool` conta o teto
  # diário de quarentenas por plano.
  def create_quarantines
    create_table :whatsapp_proxy_quarantines do |t|
      t.string :proxy_address, null: false
      t.string :pool, null: false
      t.datetime :quarantined_until, null: false
      t.string :reason, null: false
      t.timestamps
    end
    add_index :whatsapp_proxy_quarantines, :proxy_address, unique: true
  end
end
