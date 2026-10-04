# Tarefas longas do Guia (#936): "arruma os 512 nomes de contato".
#
# O modelo escreve uma RECEITA (estrutura, não texto) e uma máquina a aplica
# item a item, em lotes de 25, com amostra antes, pausa de segurança depois do
# primeiro lote e "Desfazer tudo". Cada lote é uma `Execucao` do diário (#855),
# por isso a execução ganha `task_id`, e `jobs`, a contagem de jobs que o lote
# deixou na fila (o que a pausa de segurança mostra).
#
# LGPD: o item guarda só a referência (`record_type`, `record_id`). A amostra
# (antes/depois de 10 itens) vence em 5 dias junto com a tarefa.
class CreateAutonomiaGuideTasks < ActiveRecord::Migration[7.2]
  def change
    create_tarefas
    create_itens

    change_table :autonomia_guide_executions, bulk: true do |t|
      t.references :task, foreign_key: { to_table: :autonomia_guide_tasks, on_delete: :nullify }
      t.jsonb :jobs, null: false, default: {}
    end
  end

  private

  def create_tarefas # rubocop:disable Metrics/MethodLength
    create_table :autonomia_guide_tasks do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :turno, foreign_key: { to_table: :autonomia_guide_turns, on_delete: :nullify }
      t.string :status, null: false
      t.string :descricao, null: false
      t.jsonb :receita, null: false, default: {}
      t.string :receita_digest
      %i[total feitos falhas pulados lotes].each { |coluna| t.integer coluna, null: false, default: 0 }
      t.integer :lote_tamanho, null: false, default: 25
      t.jsonb :amostra, null: false, default: []
      %i[canario relatorio].each { |coluna| t.jsonb coluna, null: false, default: {} }
      %i[custo_estimado custo teto_custo].each { |coluna| t.decimal coluna, precision: 12, scale: 6, null: false, default: 0 }
      t.integer :jev_estimado, null: false, default: 0
      t.integer :tempo_estimado, null: false, default: 0
      t.string :motivo_pausa
      t.datetime :batimento_em
      t.datetime :mensagens_conferidas_ate
      t.datetime :expira_em, null: false
      t.timestamps
    end
    add_index :autonomia_guide_tasks, [:account_id, :status]
    add_index :autonomia_guide_tasks, :expira_em
  end

  def create_itens
    create_table :autonomia_guide_task_items do |t|
      t.references :task, null: false, foreign_key: { to_table: :autonomia_guide_tasks, on_delete: :cascade }, index: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.integer :posicao, null: false
      t.string :status, null: false, default: 'pendente'
      t.string :erro
      t.string :escolha
      t.decimal :certeza, precision: 4, scale: 3
      t.timestamps
    end
    add_index :autonomia_guide_task_items, [:task_id, :posicao]
    add_index :autonomia_guide_task_items, [:task_id, :record_type, :record_id], unique: true, name: 'idx_autonomia_guide_task_items_ref'
  end
end
