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
  # O motivo que os Agentes recebem quando é a Atribuição que passa a um agente de IA.
  MOTIVO_DA_ATRIBUICAO = 'atribuicao'.freeze

  # O agente que está passando a conversa (`quem_passa`, o robô que passa, é o espelho dele nesta caixa) não a recebe
  # de volta: a regra que aponta para ele mesmo vira alguém da equipe, sem chamar os Agentes. A guarda é do CRM: para o
  # serviço dos Agentes, a área que espera pessoa e recebe a conversa de novo é uma troca válida (`passou`), e isso
  # seria o laço.
  def self.alvo(conversation:, settings:, sugestao:, quem_passa:)
    agente = alvo_da_regra(conversation, settings, sugestao)
    agente unless espelho_de?(agente, quem_passa, conversation)
  end

  # A IA não entra no rodízio: "A mesma pessoa" apontando um agente que não pode receber agora vira alguém da equipe.
  def self.so_pessoas(settings)
    settings[:pool_type] == 'ai_agent' ? settings.merge(pool_type: 'inbox', pool_id: nil) : settings
  end

  def self.alvo_da_regra(conversation, settings, sugestao)
    return ::Crm::AgentesIa.destino(settings[:pool_id], conversation) if settings[:pool_type] == 'ai_agent'
    return if settings[:selector_mode] != 'direct' || sugestao.blank?

    ::Crm::AgentesIa.rotulos(conversation)[sugestao.to_s.strip]
  end

  def self.espelho_de?(agente, robo, conversation)
    return false if agente.nil? || !robo.is_a?(AgentBot)

    ::Autonomia::Agents::AgentInbox.kept.exists?(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                                 autonomia_agent_id: agente.id, agent_bot_id: robo.id)
  end
  private_class_method :alvo_da_regra, :espelho_de?

  # `origem`: quem estava com a conversa. `pedida_por`: quem pediu; obrigatório com por: :pessoa e proibido com :crm
  # (o serviço levanta ArgumentError), então só vai quando existe. O card o serviço acha sozinho.
  def self.passar!(conversation:, agent:, por:, motivo:, origem: nil, pedida_por: nil) # rubocop:disable Metrics/ParameterLists -- o contrato do PassarParaIa
    quem = { origem: origem, pedida_por: pedida_por }.compact
    ::Autonomia::Agents::PassarParaIa.call(conversation: conversation, agent: agent, por: por, motivo: motivo,
                                           transfer_id: nil, **quem).codigo.to_s
  end

  # A Atribuição passando ao agente (Crm::Entrega#concluir_para_ia!). Erro no serviço dos Agentes não deixa a conversa
  # sem ninguém: conta como recusa ('erro'), e a entrega segue sem IA. Erro de contrato (ArgumentError) é de
  # programação e sobe. Toda tentativa deixa uma linha, só com ids e códigos; `rotulo` é o da entrega que chamou.
  def self.pela_atribuicao!(conversation:, agent:, origem:, rotulo:)
    codigo = pela_atribuicao(conversation, agent, origem)
    Rails.logger.info(
      "[crm][entrega] conversa=#{conversation.id} conta=#{conversation.account_id} #{rotulo} " \
      "desfecho=#{codigo == PASSOU ? 'com_ia' : 'ia_recusou'} agente=#{agent.id} codigo=#{codigo}"
    )
    codigo
  end

  def self.pela_atribuicao(conversation, agent, origem)
    passar!(conversation: conversation, agent: agent, por: :crm, motivo: MOTIVO_DA_ATRIBUICAO, origem: origem)
  rescue ArgumentError
    raise
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] passar ao agente falhou conversa=#{conversation.id} agente=#{agent.id} " \
                       "#{Crm::SegurarNaFilaJob.para_log(e)}")
    ficou_com_o_agente?(conversation, agent) ? PASSOU : 'erro'
  end

  # "Não trocou" e "trocou e falhou depois" (no aviso, na telemetria) são diferentes: relido sob a trava, o agente já no
  # nome, sem pessoa e sem espera, é a troca feita, e a entrega não passa a conversa a uma pessoa por cima (seriam duas
  # passagens). Numa cópia lida do banco: a conversa da entrega pode ter mudança só na memória.
  def self.ficou_com_o_agente?(conversation, agent)
    conversa = conversation.class.find(conversation.id)
    conversa.with_lock do
      conversa.assignee_id.nil? && !conversa.bot_handoff_waiting? && espelho_de?(agent, conversa.ai_assignee, conversa)
    end
  end
  private_class_method :pela_atribuicao, :ficou_com_o_agente?
end
