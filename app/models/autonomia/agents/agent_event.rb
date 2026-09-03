module Autonomia
  module Agents
    # Fase F — evento ADITIVO de operação (replied/handed_off). Imutável (só created_at).
    # Guarda apenas métricas seguras: confidence, answered_from_knowledge e um motivo de
    # handoff CURADO/truncado pelo EventLogger. NUNCA contém instruction/scaffold/prompt.
    class AgentEvent < ApplicationRecord
      self.table_name = 'autonomia_agent_events'

      belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id
      belongs_to :account

      # skipped_* (#284 · Entrega 2a): a porta de engajamento passou a conversa direto para humanos
      # sem responder (fora do público-alvo / fora do horário). Contam como handoff na aba Desempenho.
      enum event_type: { replied: 0, handed_off: 1, skipped_audience: 2, skipped_schedule: 3 }

      HANDOFF_TYPES = %w[handed_off skipped_audience skipped_schedule].freeze

      scope :in_range, ->(from, to) { where(created_at: from..to) }
      # Tudo que tirou a conversa do agente: handoff sinalizado/CRM + passadas direto pela porta.
      scope :handoffs, -> { where(event_type: HANDOFF_TYPES) }
    end
  end
end
