# Memória das IAs (#1601), PR 2: no máximo UMA tarefa de retomar o atendimento aberta por conversa (pendente ou
# atrasada). A passagem, a conversa segurada pela Entrega e a conciliação podem tentar criar ao mesmo tempo: a segunda
# esbarra aqui e reaproveita a que existe. Índice parcial (só as tarefas da memória), criado sem travar a tabela.
class AddMemoriaRetomarIndexToCrmFollowUps < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :crm_follow_ups, %i[account_id conversation_id], unique: true, algorithm: :concurrently,
                                                               name: 'idx_crm_followups_memoria_retomar_aberta',
                                                               where: "(metadata #>> '{memoria,tipo}') = 'retomar_atendimento' " \
                                                                      'AND status IN (0, 3)'
  end
end
