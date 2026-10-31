# #1430 — quanto tempo o agente espera pela ferramenta HTTP: padrão 10 s, o admin sobe até 60 s por ferramenta
# (decisão do Rodrigo, 13/10). Acima disso é o webhook que "aguarda retorno" (#1435). Default constante: o
# Postgres não reescreve a tabela.
class AddTimeoutSecondsToAutonomiaAgentTools < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_agent_tools, :timeout_seconds, :integer, null: false, default: 10
    add_check_constraint :autonomia_agent_tools, 'timeout_seconds BETWEEN 10 AND 60', name: 'autonomia_agent_tools_timeout_seconds'
  end
end
