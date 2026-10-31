# #1430 — quanto tempo o agente espera pela ferramenta HTTP: padrão 30 s, sem máximo (decisão do Rodrigo, 31/10:
# "9. B tirar"). Só zero ou negativo é recusado: seria defeito, não escolha. Default constante: o Postgres não
# reescreve a tabela.
class AddTimeoutSecondsToAutonomiaAgentTools < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_agent_tools, :timeout_seconds, :integer, null: false, default: 30
    # O check trava a tabela enquanto confere as linhas. Aqui é instantâneo: ferramenta HTTP só a equipe da plataforma
    # cria, e a hub2you tinha 0 em 31/10.
    safety_assured do
      add_check_constraint :autonomia_agent_tools, 'timeout_seconds > 0', name: 'autonomia_agent_tools_timeout_seconds'
    end
  end
end
