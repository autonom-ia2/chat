# "Meus horários" (#1195, J8-A11): cada pessoa que atende ajusta os próprios dias e horas de agendamento, sempre
# dentro dos limites da página, e pode pausar a própria agenda. Uma linha por pessoa por conta.
#
# Tabela nova (sem coluna em tabela do Chatwoot); as FKs nascem com a tabela vazia e cada uma tem índice próprio.
# `working_hours` usa o mesmo formato da página (`start_hour`, `end_hour`, `weekdays`); vazio = segue a página.
class CreateCrmAgentAvailabilities < ActiveRecord::Migration[7.2]
  def change
    create_table :crm_agent_availabilities do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :working_hours, null: false, default: {}
      t.boolean :paused, null: false, default: false
      t.timestamps
    end
    add_index :crm_agent_availabilities, [:account_id, :user_id], unique: true
  end
end
