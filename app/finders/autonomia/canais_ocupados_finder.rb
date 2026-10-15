# #1181 (L2) — caixas da conta e quem atende cada uma, em consultas fixas (sem N+1).
# - Agente nativo (vínculo kept de um agente visível na API de agentes): { kind: 'agent', agent_id, agent_name, operating,
#   caixas }. Agente parado continua dono da caixa; operating segue Agent#operating? (o escopo já tira os apagados).
#   `caixas` (#1366): quantos vínculos ativos (porta ou área) o agente tem na conta. Com 1, trocá-lo desta caixa o para,
#   e a tela avisa.
# - Atendimento automático externo, sem nome: bot de webhook na caixa ou vínculo de agente fora da API (de sistema).
# - Livre (nil): sem bot e sem vínculo kept — a mesma regra das caixas elegíveis de agents/:id/channels.
# O bot da caixa é lido pela associação da caixa: agent_bot_inboxes.account_id aceita nulo em linhas antigas.
# `areas` (#1433, tema 13): os agentes da equipe da caixa (vínculo de papel área, ativo, de agente visível na API), por
#   nome: [{ agent_id, agent_name, operating }]. Não ocupam a caixa; a tela lê daqui "Recebe quando alguém passar em".
#   Quem pode receber um agente da equipe: a caixa cujo `occupied_by` é um agente nativo com `operating` true.
class Autonomia::CanaisOcupadosFinder
  EXTERNO = { kind: 'external' }.freeze

  def initialize(account:, agents_scope:)
    @account = account
    @agents_scope = agents_scope
  end

  # [{ inbox_id:, name:, channel_type:, occupied_by:, areas: }] por nome da caixa; no máximo 6 consultas, seja qual for o número
  # de caixas.
  def call
    com_bot = caixas_com_bot
    @account.inboxes.order(:name, :id).pluck(:id, :name, :channel_type).map do |inbox_id, name, channel_type|
      { inbox_id: inbox_id, name: name, channel_type: channel_type, occupied_by: ocupante(inbox_id, com_bot),
        areas: areas_por_caixa.fetch(inbox_id, []) }
    end
  end

  private

  def ocupante(inbox_id, com_bot)
    agente = agentes[vinculos[inbox_id]]
    return nativo(*agente, caixas_por_agente.fetch(agente.first, 0)) if agente
    return EXTERNO if vinculos.key?(inbox_id) || com_bot.include?(inbox_id)

    nil
  end

  def nativo(agent_id, agent_name, status, enabled, caixas)
    { kind: 'agent', agent_id: agent_id, agent_name: agent_name, operating: enabled && status == 'active', caixas: caixas }
  end

  def caixas_por_agente
    @caixas_por_agente ||= ::Autonomia::Agents::AgentInbox.kept.where(account_id: @account.id, autonomia_agent_id: vinculos.values.uniq)
                                                          .group(:autonomia_agent_id).count
  end

  # { inbox_id => autonomia_agent_id } das portas kept da conta (uma por caixa, índice único). Quem ocupa a caixa é a
  # porta; o agente da equipe (área, #1433) não ocupa.
  def vinculos
    @vinculos ||= ::Autonomia::Agents::AgentInbox.kept.porta.where(account_id: @account.id)
                                                 .pluck(:inbox_id, :autonomia_agent_id).to_h
  end

  def agentes
    @agentes ||= @agents_scope.where(id: vinculos.values.uniq)
                              .pluck(:id, :name, :status, :enabled)
                              .index_by(&:first)
  end

  # { inbox_id => [{ agent_id:, agent_name:, operating: }] } dos agentes da equipe, numa consulta só.
  def areas_por_caixa
    @areas_por_caixa ||= @agents_scope.joins(:agent_inboxes)
                                      .merge(::Autonomia::Agents::AgentInbox.kept.area.where(account_id: @account.id))
                                      .order(:name, :id)
                                      .pluck('autonomia_agent_inboxes.inbox_id', :id, :name, :status, :enabled)
                                      .group_by(&:first)
                                      .transform_values { |linhas| linhas.map { |linha| area(*linha.drop(1)) } }
  end

  def area(agent_id, agent_name, status, enabled)
    { agent_id: agent_id, agent_name: agent_name, operating: enabled && status == 'active' }
  end

  def caixas_com_bot
    @account.inboxes.joins(:agent_bot_inbox).distinct.pluck(:id).to_set
  end
end
