# == Schema Information
#
# Table name: autonomia_agent_events
#
#  id                      :bigint           not null, primary key
#  answered_from_knowledge :boolean          default(FALSE), not null
#  confidence              :float
#  event_type              :integer          not null
#  handoff_reason          :string
#  metadata                :jsonb            not null
#  model                   :string
#  used_entry_ids          :jsonb            not null
#  created_at              :datetime         not null
#  account_id              :bigint           not null
#  autonomia_agent_id      :bigint           not null
#  conversation_id         :bigint
#  message_id              :bigint
#
# Indexes
#
#  idx_autonomia_events_agent_created                  (autonomia_agent_id,created_at)
#  idx_autonomia_events_agent_type                     (autonomia_agent_id,event_type)
#  idx_autonomia_events_message                        (message_id)
#  idx_autonomia_events_used_entry_ids                 (used_entry_ids) USING gin
#  index_autonomia_agent_events_on_account_id          (account_id)
#  index_autonomia_agent_events_on_autonomia_agent_id  (autonomia_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id)
#
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
