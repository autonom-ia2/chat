class AddReplySourcesToAutonomiaAgentEvents < ActiveRecord::Migration[7.2]
  # Só colunas (transacional). Adicionar coluna nula / com default em jsonb é metadata-only no
  # Postgres — não reescreve a tabela nem bloqueia escritas. Os índices ficam na migration seguinte
  # (20260903140100), que precisa de disable_ddl_transaction! para criá-los CONCURRENTLY.
  # Registro INTERNO das fontes usadas por resposta (Entrega 1 · #284):
  #   message_id      -> a Message outgoing postada (liga o evento ao feedback do atendente)
  #   used_entry_ids  -> ids dos knowledge_entries citados pelo modelo (só ids, nunca conteúdo)
  #   model           -> modelo que gerou a resposta
  def change
    add_column :autonomia_agent_events, :message_id, :bigint
    add_column :autonomia_agent_events, :used_entry_ids, :jsonb, null: false, default: []
    add_column :autonomia_agent_events, :model, :string

    # O model pode já estar carregado neste mesmo processo (migrations em lote): garante que o
    # EventLogger enxerga as colunas novas sem reiniciar.
    Autonomia::Agents::AgentEvent.reset_column_information if defined?(Autonomia::Agents::AgentEvent)
  end
end
