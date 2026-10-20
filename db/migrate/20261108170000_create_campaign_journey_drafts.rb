# Rascunho da "Nova campanha" no servidor (#1898, épico #1784). Quem só monta a campanha deixa ela pronta para
# disparar; quem dispara abre pela lista. Até aqui o rascunho vivia só no navegador (campaignDraft.js).
# Tabela própria do fork, sem coluna nas tabelas de campanha do Chatwoot.
# - payload: as escolhas da jornada, no formato do campaignDraft.js (nunca dado de contato).
# - email_campaign_id: o rascunho de e-mail que a jornada já cria no servidor, quando o canal é e-mail.
# FKs: apagar a conta ou a campanha de e-mail apaga o rascunho; apagar o autor só limpa o autor.
class CreateCampaignJourneyDrafts < ActiveRecord::Migration[7.2]
  def change
    create_table :campaign_journey_drafts do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.bigint :email_campaign_id
      t.string :title, null: false, default: ''
      t.string :channel, null: false, default: ''
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :campaign_journey_drafts, %i[account_id updated_at]
    add_index :campaign_journey_drafts, :email_campaign_id
    add_index :campaign_journey_drafts, :user_id
    add_foreign_key :campaign_journey_drafts, :accounts, on_delete: :cascade
    add_foreign_key :campaign_journey_drafts, :users, on_delete: :nullify
    add_foreign_key :campaign_journey_drafts, :email_campaigns, on_delete: :cascade
  end
end
