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
  # Uma pessoa já está no nome: o serviço recusa :crm e :ia, e a conversa fica com ela.
  FICA_COM_A_PESSOA = 'pessoa_atribuida'.freeze

  # O agente que está passando a conversa (o robô gravado nela é o espelho dele nesta caixa) não a recebe de volta: a
  # regra que aponta para ele mesmo vira alguém da equipe, sem chamar os Agentes. A guarda é do CRM: para o serviço dos
  # Agentes, a área que espera pessoa e recebe a conversa de novo é uma troca válida (`passou`), e isso seria o laço.
  def self.alvo(conversation:, settings:, sugestao:)
    agente = alvo_da_regra(conversation, settings, sugestao)
    agente unless esta_passando?(agente, conversation)
  end

  def self.alvo_da_regra(conversation, settings, sugestao)
    return ::Crm::AgentesIa.destino(settings[:pool_id], conversation) if settings[:pool_type] == 'ai_agent'
    return if settings[:selector_mode] != 'direct' || sugestao.blank?

    ::Crm::AgentesIa.rotulos(conversation)[sugestao.to_s.strip]
  end

  # O valor do banco: na passagem do robô (ConversationBotHandoff#bot_handoff!) ele já saiu da memória.
  def self.esta_passando?(agente, conversation)
    return false if agente.nil? || conversation.attribute_in_database('ai_assignee_type') != 'AgentBot'

    ::Autonomia::Agents::AgentInbox.kept.exists?(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                                 autonomia_agent_id: agente.id,
                                                 agent_bot_id: conversation.attribute_in_database('assignee_agent_bot_id'))
  end
  private_class_method :alvo_da_regra, :esta_passando?

  # `origem`: quem estava com a conversa. `pedida_por`: quem pediu; obrigatório com por: :pessoa e proibido com :crm
  # (o serviço levanta ArgumentError), então só vai quando existe. O card o serviço acha sozinho.
  def self.passar!(conversation:, agent:, por:, motivo:, origem: nil, pedida_por: nil) # rubocop:disable Metrics/ParameterLists -- o contrato do PassarParaIa
    quem = { origem: origem, pedida_por: pedida_por }.compact
    ::Autonomia::Agents::PassarParaIa.call(conversation: conversation, agent: agent, por: por, motivo: motivo,
                                           transfer_id: nil, **quem).codigo.to_s
  end
end
