# Excluir conversa (#2144): o registro do agente de IA da conversa apagada é limpo por `conversation_id`
# (Autonomia::Agents::RegistroDaConversaExcluida). Em autonomia_agent_events não havia índice que começasse pela coluna:
# cada conversa apagada leria todos os eventos da conta. As execuções de ferramenta já têm o delas
# (idx_autonomia_tool_runs_conversation).
class AddIndexAutonomiaAgentEventsOnConversationId < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  NOME = 'idx_autonomia_events_conversation'.freeze

  def up
    add_index :autonomia_agent_events, :conversation_id, name: NOME, where: 'conversation_id IS NOT NULL',
                                                         algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :autonomia_agent_events, name: NOME, algorithm: :concurrently, if_exists: true
  end
end
