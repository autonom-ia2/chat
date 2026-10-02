# O que o Guia fez, com o estado de antes, para poder desfazer por 5 dias (#855).
#
# Uma execução é um turno do Guia; cada mudança é UMA linha do banco criada,
# alterada ou apagada durante esse turno. O estado de antes é guardado como o
# Postgres o tem (row_to_json), sem passar pelo Rails: campo cifrado continua
# cifrado aqui, e a volta é exata.
class CreateAutonomiaGuideExecutions < ActiveRecord::Migration[7.2]
  def change
    criar_execucoes
    criar_mudancas
  end

  private

  def criar_execucoes
    create_table :autonomia_guide_executions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :passos, null: false, default: []
      t.jsonb :pendencias, null: false, default: []
      t.datetime :expira_em, null: false
      t.datetime :desfeita_em
      t.references :desfeita_por, foreign_key: { to_table: :users, on_delete: :nullify }
      t.jsonb :relatorio_desfazer, null: false, default: {}
      t.timestamps
    end
    add_index :autonomia_guide_executions, [:account_id, :user_id, :created_at],
              name: 'idx_autonomia_guide_executions_dono'
    add_index :autonomia_guide_executions, :expira_em
  end

  def criar_mudancas
    create_table :autonomia_guide_changes do |t|
      t.references :execution, null: false,
                               foreign_key: { to_table: :autonomia_guide_executions, on_delete: :cascade }
      t.integer :passo, null: false
      t.integer :ordem, null: false
      t.string :tabela, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.string :operacao, null: false
      t.jsonb :antes, null: false, default: {}
      t.jsonb :depois, null: false, default: {}
      t.timestamps
    end
    add_index :autonomia_guide_changes, [:execution_id, :ordem]
  end
end
