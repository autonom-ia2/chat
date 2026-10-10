# #1181 (L1) — números da semana por agente, para a lista inteira em consultas fixas (sem N+1).
# Mesma janela e mesma regra do Desempenho (Autonomia::Agents::Analytics, range 7d), para os números não divergirem:
# - answered: conversas distintas com resposta do agente (evento replied) na janela;
# - handed: conversas distintas atendidas na janela que foram passadas para a equipe — evento de handoff do agente
#   na janela ou conversation_bot_handoff do core na janela (o outcome handed_off do Desempenho).
# Só conta conversa que existe na própria conta (o Desempenho lê as conversas pela conta do agente).
class Autonomia::AgentesSemanaFinder
  RANGE = '7d'.freeze
  CORE_HANDOFF = 'conversation_bot_handoff'.freeze

  CONVERSA_DA_CONTA = <<~SQL.squish.freeze
    INNER JOIN conversations ON conversations.id = autonomia_agent_events.conversation_id
      AND conversations.account_id = autonomia_agent_events.account_id
  SQL

  PASSADA_PARA_A_EQUIPE = <<~SQL.squish.freeze
    (EXISTS (
      SELECT 1 FROM autonomia_agent_events passagem
      WHERE passagem.autonomia_agent_id = autonomia_agent_events.autonomia_agent_id
        AND passagem.account_id = autonomia_agent_events.account_id
        AND passagem.conversation_id = autonomia_agent_events.conversation_id
        AND passagem.event_type IN (:tipos_de_passagem)
        AND passagem.created_at BETWEEN :from AND :to
    ) OR EXISTS (
      SELECT 1 FROM reporting_events core
      WHERE core.account_id = autonomia_agent_events.account_id
        AND core.conversation_id = autonomia_agent_events.conversation_id
        AND core.name = :core_handoff
        AND core.event_end_time BETWEEN :from AND :to
    ))
  SQL

  attr_reader :from, :to

  def initialize(account:, agent_ids:)
    @account = account
    @agent_ids = agent_ids
    @to = Time.current
    @from = (::Autonomia::Agents::Analytics::RANGES.fetch(RANGE) - 1).days.ago.beginning_of_day
  end

  def range
    RANGE
  end

  # [{ agent_id:, answered:, handed: }] na ordem de agent_ids; agente sem conversas sai com zeros.
  def call
    return [] if @agent_ids.empty?

    answered = conversas_por_agente(eventos.replied)
    handed = conversas_por_agente(eventos.atendimentos.where(PASSADA_PARA_A_EQUIPE, passagem_binds))
    @agent_ids.map { |id| { agent_id: id, answered: answered[id].to_i, handed: handed[id].to_i } }
  end

  private

  def eventos
    ::Autonomia::Agents::AgentEvent.where(account_id: @account.id, autonomia_agent_id: @agent_ids)
                                   .in_range(@from, @to)
                                   .joins(CONVERSA_DA_CONTA)
  end

  def conversas_por_agente(scope)
    scope.group(:autonomia_agent_id).distinct.count(:conversation_id)
  end

  def passagem_binds
    event_types = ::Autonomia::Agents::AgentEvent.event_types
    { tipos_de_passagem: event_types.values_at(*::Autonomia::Agents::AgentEvent::HANDOFF_TYPES),
      core_handoff: CORE_HANDOFF, from: @from, to: @to }
  end
end
