# #1181 (L2) — caixas da conta e quem atende cada uma, em consultas fixas (sem N+1).
# - Agente nativo (vínculo kept de um agente visível na API de agentes): { kind: 'agent', agent_id, agent_name, operating,
#   caixas }. Agente parado continua dono da caixa; operating segue Agent#operating? (o escopo já tira os apagados).
#   `caixas` (#1366): quantos vínculos ativos (porta ou área) o agente tem na conta. Com 1, trocá-lo desta caixa o para,
#   e a tela avisa.
# - Atendimento automático externo, sem nome: bot de webhook na caixa ou vínculo de agente fora da API (de sistema).
#   Agente de outro sistema (#1648: AgentBotInbox de um AgentBot que não é espelho) diz qual é e se atende:
#   { kind: 'external', agent_bot_id, operating } (operating = AgentBotInbox ativo). A lista de Agentes e a página dele
#   leem daqui onde ele atende primeiro.
# - Livre (nil): sem bot e sem vínculo kept — a mesma regra das caixas elegíveis de agents/:id/channels.
# O bot da caixa é lido pela associação da caixa: agent_bot_inboxes.account_id aceita nulo em linhas antigas.
# `areas` (#1433, tema 13): os agentes da equipe da caixa (vínculo de papel área, ativo, de agente visível na API), por
#   nome: [{ agent_id, agent_name, operating }]. Não ocupam a caixa; a tela lê daqui "Recebe quando alguém passar em".
#   Quem pode receber um agente da equipe: a caixa cujo `occupied_by` é um agente nativo com `operating` true, ou a
#   caixa só de pessoas.
# `so_de_pessoas` (#1433): sem porta e sem robô de fora (o `occupied_by` nil), a mesma regra do AgentInbox. O agente da
#   equipe entra e só responde a conversa que alguém passar para ele.
class Autonomia::CanaisOcupadosFinder
  EXTERNO = { kind: 'external' }.freeze

  def initialize(account:, agents_scope:)
    @account = account
    @agents_scope = agents_scope
  end

  # [{ inbox_id:, name:, channel_type:, occupied_by:, so_de_pessoas:, areas: }] por nome da caixa; no máximo 7 consultas, seja qual for o número
  # de caixas.
  def call
    com_bot = caixas_com_bot
    robos_de_outro_sistema # sempre, para o número de consultas não depender das caixas
    @account.inboxes.order(:name, :id).pluck(:id, :name, :channel_type).map do |inbox_id, name, channel_type|
      ocupado_por = ocupante(inbox_id, com_bot)
      { inbox_id: inbox_id, name: name, channel_type: channel_type, occupied_by: ocupado_por, so_de_pessoas: ocupado_por.nil?,
        areas: areas_por_caixa.fetch(inbox_id, []) }
    end
  end

  private

  def ocupante(inbox_id, com_bot)
    agente = agentes[vinculos[inbox_id]]
    return nativo(*agente, caixas_por_agente.fetch(agente.first, 0)) if agente
    return EXTERNO if vinculos.key?(inbox_id)
    return de_outro_sistema(*robos_de_outro_sistema[inbox_id]) if robos_de_outro_sistema.key?(inbox_id)
    return EXTERNO if com_bot.include?(inbox_id)

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

  def de_outro_sistema(agent_bot_id, status)
    { kind: 'external', agent_bot_id: agent_bot_id, operating: status == 'active' }
  end

  # { inbox_id => [agent_bot_id, status] } dos agentes de outro sistema (#1648), pela associação da caixa como
  # caixas_com_bot. Com mais de um na caixa (dado antigo), fica o primeiro por id.
  def robos_de_outro_sistema
    @robos_de_outro_sistema ||= @account.inboxes.joins(:agent_bot_inbox)
                                        .where.not(agent_bot_inboxes: { agent_bot_id: ::Autonomia::Agents::AgentInbox.espelhos })
                                        .order('agent_bot_inboxes.id')
                                        .pluck(:id, 'agent_bot_inboxes.agent_bot_id', 'agent_bot_inboxes.status')
                                        .each_with_object({}) { |(inbox_id, bot_id, status), mapa| mapa[inbox_id] ||= [bot_id, status] }
  end

  def caixas_com_bot
    @account.inboxes.joins(:agent_bot_inbox).distinct.pluck(:id).to_set
  end
end
