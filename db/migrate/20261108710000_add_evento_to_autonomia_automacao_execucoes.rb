# #2414 F3 (#2459, PR-C): a marca por evento. O mesmo evento entregue duas vezes (o EventDispatcherJob tenta de novo)
# abre uma execução só, mesmo depois que a primeira fechou: o índice aberto (idx_autonomia_automacao_execucoes_abertas)
# só vale enquanto ela anda. `evento` é "mensagem:<id>" no gatilho mensagem.criada e nulo nos outros, que não têm id de
# evento. A coluna sai junto com a execução na limpeza (LimparRegistrosJob).
#
# Sem transação: o índice entra com CONCURRENTLY (parcial, só as execuções com evento). A coluna nasce nula em todas.
class AddEventoToAutonomiaAutomacaoExecucoes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    add_column :autonomia_automacao_execucoes, :evento, :string unless column_exists?(:autonomia_automacao_execucoes, :evento)
    add_index :autonomia_automacao_execucoes, %i[automacao_id evento],
              unique: true, where: 'evento IS NOT NULL', name: 'idx_autonomia_automacao_execucoes_evento',
              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :autonomia_automacao_execucoes, name: 'idx_autonomia_automacao_execucoes_evento', algorithm: :concurrently,
                                                 if_exists: true
    remove_column :autonomia_automacao_execucoes, :evento, if_exists: true
  end
end
