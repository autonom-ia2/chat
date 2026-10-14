# Avisos de uma reunião (#1192, J5-A1): uma linha por aviso (ao marcar, remarcada, 1 dia antes, 1 hora antes), com
# vencimento e resultado. O cron pega as pendentes vencidas pelo índice (status, due_at); a unicidade
# (reunião, tipo) impede dois avisos iguais para a mesma reunião.
class CreateCrmMeetingNotices < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_meeting_notices do |t|
      t.references :meeting, null: false, foreign_key: { to_table: :crm_meetings, on_delete: :cascade }, index: false
      t.bigint :account_id, null: false
      t.string :kind, null: false
      t.datetime :due_at, null: false
      t.integer :status, default: 0, null: false
      t.string :skip_reason
      t.datetime :sent_at
      t.bigint :message_id
      t.integer :attempts, default: 0, null: false
      t.string :error_code
      t.timestamps
    end
    add_index :crm_meeting_notices, [:meeting_id, :kind], unique: true
    add_index :crm_meeting_notices, [:status, :due_at]
    add_index :crm_meeting_notices, [:account_id, :sent_at]
  end
end
