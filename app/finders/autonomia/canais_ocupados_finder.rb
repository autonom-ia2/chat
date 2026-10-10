# #1181 (L2) — caixas da conta e quem atende cada uma, em consultas fixas (sem N+1).
# - Agente nativo (vínculo kept de um agente visível na API de agentes): { kind: 'agent', agent_id, agent_name, operating }.
#   Agente parado continua dono da caixa; operating segue Agent#operating? (o escopo já tira os apagados).
# - Atendimento automático externo, sem nome: bot de webhook na caixa ou vínculo de agente fora da API (de sistema).
# - Livre (nil): sem bot e sem vínculo kept — a mesma regra das caixas elegíveis de agents/:id/channels.
# O bot da caixa é lido pela associação da caixa: agent_bot_inboxes.account_id aceita nulo em linhas antigas.
class Autonomia::CanaisOcupadosFinder
  EXTERNO = { kind: 'external' }.freeze

  def initialize(account:, agents_scope:)
    @account = account
    @agents_scope = agents_scope
  end

  # [{ inbox_id:, name:, channel_type:, occupied_by: }] por nome da caixa; no máximo 4 consultas, seja qual for o número de caixas.
  def call
    com_bot = caixas_com_bot
    @account.inboxes.order(:name, :id).pluck(:id, :name, :channel_type).map do |inbox_id, name, channel_type|
      { inbox_id: inbox_id, name: name, channel_type: channel_type, occupied_by: ocupante(inbox_id, com_bot) }
    end
  end

  private

  def ocupante(inbox_id, com_bot)
    agente = agentes[vinculos[inbox_id]]
    return nativo(*agente) if agente
    return EXTERNO if vinculos.key?(inbox_id) || com_bot.include?(inbox_id)

    nil
  end

  def nativo(agent_id, agent_name, status, enabled)
    { kind: 'agent', agent_id: agent_id, agent_name: agent_name, operating: enabled && status == 'active' }
  end

  # { inbox_id => autonomia_agent_id } dos vínculos kept da conta (um por caixa, índice único).
  def vinculos
    @vinculos ||= ::Autonomia::Agents::AgentInbox.kept.where(account_id: @account.id)
                                                 .pluck(:inbox_id, :autonomia_agent_id).to_h
  end

  def agentes
    @agentes ||= @agents_scope.where(id: vinculos.values.uniq)
                              .pluck(:id, :name, :status, :enabled)
                              .index_by(&:first)
  end

  def caixas_com_bot
    @account.inboxes.joins(:agent_bot_inbox).distinct.pluck(:id).to_set
  end
end
