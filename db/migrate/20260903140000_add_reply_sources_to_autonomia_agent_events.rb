class AddReplySourcesToAutonomiaAgentEvents < ActiveRecord::Migration[7.2]
  # Aditiva e barata: colunas nulas/default em jsonb são metadata-only no Postgres e a tabela de
  # eventos é pequena. Registro INTERNO das fontes usadas por resposta (Entrega 1 · #284):
  #   message_id      -> a Message outgoing postada (liga o evento ao feedback do atendente)
  #   used_entry_ids  -> ids dos knowledge_entries citados pelo modelo (só ids, nunca conteúdo)
  #   model           -> modelo que gerou a resposta
  def change
    add_column :autonomia_agent_events, :message_id, :bigint
    add_column :autonomia_agent_events, :used_entry_ids, :jsonb, null: false, default: []
    add_column :autonomia_agent_events, :model, :string

    add_index :autonomia_agent_events, :message_id, name: 'idx_autonomia_events_message'
    add_index :autonomia_agent_events, :used_entry_ids, using: :gin, name: 'idx_autonomia_events_used_entry_ids'

    # O model pode já estar carregado neste mesmo processo (migrations em lote): garante que o
    # EventLogger enxerga as colunas novas sem reiniciar.
    Autonomia::Agents::AgentEvent.reset_column_information if defined?(Autonomia::Agents::AgentEvent)
  end
end
