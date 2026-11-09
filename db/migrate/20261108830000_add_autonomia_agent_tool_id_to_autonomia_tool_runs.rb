# #1430 — a execução de uma consulta HTTP em segundo plano (a ferramenta cadastrada, com a flag
# `agente_ferramenta_em_segundo_plano`, numa conversa) aponta para a ferramenta. O job a resolve por este id, nunca pelo
# slug: o slug de uma HTTP podia ser igual ao de uma nativa (`cotar_seguro`), e pelo catálogo a consulta cairia na Lia.
# Nula nas execuções das nativas.
# - Sem FK: apagar a ferramenta (ou o agente, em cascata) não pode esbarrar no histórico de execuções. O job que não acha
#   a ferramenta encerra a execução como `ferramenta_indisponivel`.
# - O add_column nulo é só metadado; o lock_timeout do StrongMigrations cobre o ACCESS EXCLUSIVE curto.
# - O índice é criado concurrently, fora da transação. A tabela é pequena (só execuções assíncronas); rodar de novo não
#   muda nada.
class AddAutonomiaAgentToolIdToAutonomiaToolRuns < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'idx_autonomia_tool_runs_agent_tool'.freeze

  def up
    add_column :autonomia_agent_tool_runs, :autonomia_agent_tool_id, :bigint, if_not_exists: true
    add_index :autonomia_agent_tool_runs, :autonomia_agent_tool_id, name: INDICE, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :autonomia_agent_tool_runs, name: INDICE, algorithm: :concurrently, if_exists: true
    remove_column :autonomia_agent_tool_runs, :autonomia_agent_tool_id, if_exists: true
  end
end
