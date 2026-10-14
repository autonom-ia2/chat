# Modelos WhatsApp B (#1330, épico #1320): o que só o Chat2You sabe de um modelo da Meta. A lista sincronizada da caixa
# (`channel_whatsapp.message_templates`, do Chatwoot) é regravada a cada sync e zerada na troca de conta, por isso o
# estado do fork fica aqui. Sem linha, nada muda: o modelo aparece pelo nome técnico.
# - waba_id: a conta do WhatsApp (WABA) da caixa no momento em que o perfil foi gravado.
# - fields: chave do catálogo de campos por variável ({ "1": "cliente.primeiro_nome" }).
# - header_media: o arquivo de exemplo do topo (handle da Meta, nome, tipo, tamanho); o arquivo fica no ActiveStorage.
# - system_owner: quem da plataforma usa o modelo ('agendamento', 'anuncios', 'satisfacao'); nulo = da pessoa.
class CreateWhatsappTemplateProfiles < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_template_profiles do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :waba_id, null: false
      t.string :meta_template_id
      t.string :name, null: false
      t.string :language, null: false
      t.string :friendly_name
      t.jsonb :fields, null: false, default: {}
      t.jsonb :header_media, null: false, default: {}
      t.string :system_owner
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.timestamps
    end
    add_index :whatsapp_template_profiles, [:inbox_id, :name, :language], unique: true, name: 'idx_whatsapp_template_profiles_unique'
    add_index :whatsapp_template_profiles, [:account_id, :waba_id], name: 'idx_whatsapp_template_profiles_waba'
  end
end
