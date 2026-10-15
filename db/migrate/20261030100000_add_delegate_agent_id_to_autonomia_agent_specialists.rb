# Tema 14 (#1434) — o ajudante: o Specialist pode apontar para OUTRO agente da conta (tabela do fork, nenhuma do
# Chatwoot). A linha com `delegate_agent_id` é o vínculo principal → ajudante; a instrução, a base e as ferramentas vêm
# do agente apontado. Um principal tem no máximo um vínculo com cada ajudante (índice único parcial). Apagar o agente
# ajudante apaga os vínculos dele (on_delete cascade); o caminho normal é o soft delete, que só tira o ajudante do turno.
#
# Aditiva e sem backfill: as linhas de hoje (os especialistas da Lia) ficam com NULL e nada muda para elas.
class AddDelegateAgentIdToAutonomiaAgentSpecialists < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_agent_specialists, :delegate_agent_id, :bigint
    add_foreign_key :autonomia_agent_specialists, :autonomia_agents, column: :delegate_agent_id, on_delete: :cascade
    add_index :autonomia_agent_specialists, :delegate_agent_id,
              where: 'delegate_agent_id IS NOT NULL', name: 'idx_autonomia_agent_specialists_delegate'
    add_index :autonomia_agent_specialists, [:autonomia_agent_id, :delegate_agent_id],
              unique: true, where: 'delegate_agent_id IS NOT NULL', name: 'idx_autonomia_agent_specialists_par_delegate'
  end
end
