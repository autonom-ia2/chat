# Autorização do dono para o sistema criar modelos da Meta (#1586, épico #1585): registro append-only de quem ligou ou
# desligou cada marca (utility, marketing), quando, a versão e o texto exato do aviso e os preços mostrados. O estado
# atual é a última linha por (conta, marca). Sem updated_at: linha gravada não muda.
# Tabela nova: os índices nascem dentro do create_table, sem concurrently. Usuário apagado não apaga o registro.
class CreateWhatsappTemplateConsents < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_template_consents do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.string :marca, null: false
      t.string :acao, null: false
      t.string :versao_aviso, null: false
      t.text :texto_aviso, null: false
      t.jsonb :precos, null: false, default: {}
      t.datetime :created_at, null: false
      t.index [:account_id, :created_at], name: 'idx_whatsapp_template_consents_account_created'
      t.index [:account_id, :marca, :created_at], name: 'idx_whatsapp_template_consents_account_marca_created'
    end
  end
end
