# #1460 — lembrete que repete. A série guarda a regra (todo dia, toda semana nos dias escolhidos, todo dia X do mês,
# todo ano), o fim (nunca, até um dia, N vezes), o fuso e quem recebe. Cada vez vira uma linha normal em
# crm_follow_ups (series_id + occurrence_at), criada pelo Crm::FollowUpSeriesMaterializerJob: o aviso, o popup e o
# calendário continuam lendo crm_follow_ups como hoje. Tabela nova do fork; nenhuma tabela do Chatwoot muda aqui.
#
# card_id, contact_id e company_id são opcionais (#1461: lembrete só no calendário, de um cliente sem negócio ou de
# uma empresa, criado pela ficha do Relacionamento).
class CreateCrmFollowUpSeries < ActiveRecord::Migration[7.2]
  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- a tabela nova inteira num create_table só
    create_table :crm_follow_up_series do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :card, foreign_key: { to_table: :crm_cards, on_delete: :cascade }
      t.references :contact, foreign_key: { on_delete: :cascade }
      t.references :company, foreign_key: { on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.integer :automation_mode, null: false, default: 0
      t.integer :frequency, null: false
      t.integer :weekdays, array: true, null: false, default: []
      t.boolean :weekdays_only, null: false, default: false
      t.datetime :starts_at, null: false
      t.string :timezone, null: false, default: 'UTC'
      t.integer :ends_mode, null: false, default: 0
      t.date :ends_on
      t.integer :occurrences_count
      t.integer :status, null: false, default: 0
      t.datetime :paused_at
      t.datetime :ended_at
      t.integer :recipient_mode, null: false, default: 0
      t.bigint :recipient_user_ids, array: true, null: false, default: []
      t.references :recipient_team, foreign_key: { to_table: :teams, on_delete: :nullify }
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
      t.index [:account_id, :status], name: 'idx_crm_follow_up_series_account_status'
    end
  end
end
