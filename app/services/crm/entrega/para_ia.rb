# #1593 — quando a regra da Atribuição leva a conversa a um AGENTE DE IA, e não a uma pessoa:
# - "A mesma pessoa" é um agente (pool_type 'ai_agent', pool_id = id do agente);
# - ou "Se o cliente pedir alguém pelo nome" está ligado e a IA do CRM devolveu, na `sugestao`, o rótulo de um agente
#   que pode receber a conversa (Crm::AgentesIa.rotulos). Quem entende o pedido é o modelo; aqui é igualdade com a
#   lista que ele recebeu.
#
# O agente precisa estar entre os destinos possíveis da conversa (regra dos Agentes). Parado, sem vínculo na caixa ou
# sem a Fase 2: não há alvo, e a regra cai para alguém da equipe. A IA nunca entra no rodízio.
#
# `passar!` é o ÚNICO lugar do CRM que chama o serviço dos Agentes (Autonomia::Agents::PassarParaIa): o motor de
# entrega e o "Passar para…" da conversa passam por aqui. Devolve o código do serviço como texto: 'passou',
# 'ja_e_o_dono' (ok, sem troca) ou o da recusa.
class Crm::Entrega::ParaIa
  PASSOU = 'passou'.freeze

  def self.alvo(conversation:, settings:, sugestao:)
    return ::Crm::AgentesIa.destino(settings[:pool_id], conversation) if settings[:pool_type] == 'ai_agent'
    return if settings[:selector_mode] != 'direct' || sugestao.blank?

    ::Crm::AgentesIa.rotulos(conversation)[sugestao.to_s.strip]
  end

  def self.passar!(conversation:, agent:, por:, motivo:, origem: nil)
    ::Autonomia::Agents::PassarParaIa.call(conversation: conversation, agent: agent, por: por, motivo: motivo,
                                           origem: origem, transfer_id: nil).codigo.to_s
  end
end
