# Conversa aberta na campanha do WhatsApp oficial (#1335, épico #1320): quem falou com a caixa nas últimas 24 horas
# recebe uma mensagem escrita, sem modelo; os outros recebem o modelo. Tabelas do fork, sem coluna nas do Chatwoot.
# - campaign_free_texts: o texto da campanha (campos na sintaxe do catálogo, {{cliente.primeiro_nome}}), um por campanha.
# - campaign_free_text_deliveries: quem recebeu o texto (o id da Meta da mensagem livre e a Message da conversa). Se a
#   Meta recusar com 131047 (janela fechada), a pessoa recebe o modelo, uma vez só (fell_back_at).
class CreateCampaignFreeTexts < ActiveRecord::Migration[7.2]
  def up
    create_free_texts
    create_deliveries
  end

  # Só tabelas do fork: voltar apaga as duas, sem tocar em nada do Chatwoot.
  def down
    drop_table :campaign_free_text_deliveries
    drop_table :campaign_free_texts
  end

  private

  def create_free_texts
    create_table :campaign_free_texts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :campaign, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :content, null: false
      t.timestamps
    end
  end

  def create_deliveries
    create_table :campaign_free_text_deliveries do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :campaign, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.bigint :campaign_recipient_id, null: false
      t.bigint :inbox_id, null: false
      t.string :source_id, null: false
      # A Message gravada na conversa: o Híbrido troca o source_id dela pelo id do WAHA quando assume o envio, então a
      # queda acha a mensagem pelo id, não pelo source_id.
      t.bigint :message_id
      t.datetime :fell_back_at
      t.timestamps
    end
    add_index :campaign_free_text_deliveries, :campaign_recipient_id, unique: true,
                                                                      name: 'idx_campaign_free_text_deliveries_recipient'
    add_index :campaign_free_text_deliveries, :message_id
    add_index :campaign_free_text_deliveries, [:inbox_id, :source_id], unique: true,
                                                                       name: 'idx_campaign_free_text_deliveries_source'
  end
end
