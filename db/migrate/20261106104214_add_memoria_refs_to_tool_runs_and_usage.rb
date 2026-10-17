# Memória das IAs (#1601), PR 3: o card em foco na abertura de uma execução de ferramenta (W5) e, na telemetria de custo,
# o agente e o card (adendo 9). Colunas nulas, sem índice. São tabelas quentes: o ADD COLUMN pede ACCESS EXCLUSIVE, e
# atrás de uma transação longa ficaria na fila travando a avaliação de card e os agentes. Com lock_timeout de 5 s a
# migration falha rápido e o deploy aborta limpo (rodar de novo depois). SET LOCAL: vale só na transação desta migration.
class AddMemoriaRefsToToolRunsAndUsage < ActiveRecord::Migration[7.2]
  def up
    execute "SET LOCAL lock_timeout = '5s'"
    add_column :autonomia_agent_tool_runs, :card_id, :bigint
    add_column :crm_ai_usage_events, :agent_id, :bigint
    add_column :crm_ai_usage_events, :card_id, :bigint
  end

  def down
    execute "SET LOCAL lock_timeout = '5s'"
    remove_column :crm_ai_usage_events, :card_id
    remove_column :crm_ai_usage_events, :agent_id
    remove_column :autonomia_agent_tool_runs, :card_id
  end
end
