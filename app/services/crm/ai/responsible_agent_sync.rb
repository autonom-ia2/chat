# Entrega a conversa ao agente de IA responsável pelo assunto em atendimento (#1447, contrato com Agentes IA #1433).
#
# Quem atende é o robô da conversa (ai_assignee). Quando o assunto em atendimento é de um funil que, naquela caixa,
# tem um agente responsável (Crm::InboxAiAgent), a conversa passa para ele; sem responsável, volta para a porta. Roda
# no job (ou em linha, na ordem do turno), sob a trava da conversa, e confere tudo de novo com a conversa relida.
#
# A troca é SÓ pelo serviço de passagem dos Agentes (#1606): Autonomia::Agents::PassarParaIa, `por: :crm`, com o MOTIVO
# do disparo (foco, pipeline ou abrir) na passagem e no evento, origem = o robô que atendia. Ele troca o dono, grava a
# passagem (Crm::Passagens) e, depois do commit, publica o EVENTO_TROCA. Um escritor, um evento: o Sync não publica
# nada por conta própria. Recusa do serviço (`pessoa_atribuida`, `nao_atende_cliente`, `sem_vinculo_na_caixa`…) não
# troca e fica no log; `ja_e_o_dono`, nada a fazer.
#
# Nada é pedido quando:
# - a conta está sem a Fase 2 dos Agentes (sem área, quem responde é sempre a porta);
# - uma pessoa está atribuída (ela vence: a decisão "a" mostra a ela a sugestão), ou a conversa espera uma pessoa
#   (espera do robô ou marca do motor de entrega);
# - nenhum robô atende a conversa agora (sem ai_assignee): entregar a um robô seria tirá-la da fila de pessoas;
# - a conversa não está aberta nem pendente (resolvida ou adiada): entregar a um robô a reabriria;
# - o destino já é quem atende.
# Funil arquivado, fora da caixa, com a IA do funil desligada, cujo responsável está parado ou não é mais área da caixa:
# conta como funil sem responsável.
#
# Volta para a porta (a porta dos Agentes na caixa, Autonomia::Agents::QuemResponde.porta_da_caixa) quando o assunto em
# atendimento é de um funil sem responsável: o foco passou para outro card (FOCO) ou o próprio card mudou de funil
# (PIPELINE). Só volta quem atende por um vínculo nosso da caixa: um robô externo com a conversa não é tirado. O pedido
# do agente (ABRIR) nunca devolve à porta sozinho. Porta que não é agente nosso (robô externo): nada a pedir, fica no log.
#
# A troca fica também na atividade do card (ai_agent_changed), com o transfer_id do pedido do agente
# (Crm::Subjects::Abrir) quando houver, que segue para a passagem e para o evento.
class Crm::Ai::ResponsibleAgentSync
  PIPELINE = 'pipeline'.freeze
  FOCO = 'foco'.freeze
  ABRIR = 'abrir'.freeze
  MOTIVOS = [PIPELINE, FOCO, ABRIR].freeze
  # Os motivos em que o assunto em atendimento sem responsável devolve a conversa à porta.
  VOLTA_PARA_A_PORTA = [PIPELINE, FOCO].freeze
  EVENTO = 'ai_agent_changed'.freeze
  EVENTO_TROCA = 'crm.ai.responsible_agent_changed'.freeze
  # O pedido do agente (Abrir) vira troca no job logo em seguida; mais velho que isto, o transfer_id não é dele.
  JANELA_DO_PEDIDO = 10.minutes

  Resultado = Struct.new(:trocou, :de_agent_bot_id, :para_agent_bot_id, :autonomia_agent_id, :transfer_id, :motivo,
                         :codigo, keyword_init: true)

  # Só enfileira em conta que configurou algum responsável: sem linha, nada a fazer.
  def self.agendar(account_id:, conversation_id:, motivo:, card_id: nil)
    return unless Crm::InboxAiAgent.exists?(account_id: account_id)

    Crm::Ai::ResponsibleAgentSyncJob.perform_later(conversation_id, motivo, card_id)
  end

  # Conversas do card que podem estar em atendimento: a principal e as vinculadas, abertas ou pendentes.
  def self.agendar_para_card(card, motivo:)
    return unless Crm::InboxAiAgent.exists?(account_id: card.account_id)

    ids = ([card.conversation_id] + card.card_conversations.pluck(:conversation_id)).compact.uniq
    Conversation.where(id: ids, status: %i[open pending]).pluck(:id).each do |conversation_id|
      Crm::Ai::ResponsibleAgentSyncJob.perform_later(conversation_id, motivo, card.id)
    end
  end

  # card_id: com motivo PIPELINE, o card que mudou de funil; só vale se ele for o assunto em atendimento.
  def initialize(conversation:, motivo:, card_id: nil)
    @conversation = conversation
    @account = conversation.account
    @motivo = motivo.to_s
    @card_id = card_id
  end

  def perform
    resultado = Resultado.new(trocou: false, motivo: @motivo)
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      resultado = sincronizar || resultado
    end
    resultado
  end

  private

  def sincronizar
    return unless conversa_com_robo?

    card = card_em_atendimento
    return if card.nil?

    destino = destino_para(card)
    return if destino.nil? || destino[:bot].id == @conversation.assignee_agent_bot_id

    trocar(card, destino)
  end

  # Sem a Fase 2 não há área nem passagem entre IAs (o PassarParaIa recusaria): nada a pedir. A espera de pessoa e a
  # marca do motor de entrega (convite ou segurando) são da pessoa: o PassarParaIa as encerraria.
  def conversa_com_robo?
    Crm::Ai::Config.areas_ligadas?(@account) && (@conversation.open? || @conversation.pending?) &&
      @conversation.assignee_id.blank? && !@conversation.bot_handoff_waiting? && !@conversation.crm_delivery_pending? &&
      @conversation.ai_assignee.is_a?(AgentBot)
  end

  # A regra única de "qual funil manda" (#1606, Crm::Assunto.funil_atual), relida sob a trava.
  def card_em_atendimento
    card = Crm::Assunto.funil_atual(@conversation)
    return if card.nil?
    return if @motivo == PIPELINE && card.id != @card_id.to_i

    card
  end

  # { bot:, agente: } para quem a conversa vai, ou nil quando nada troca.
  # Porta pausada (ou interna, de sistema): o PassarParaIa recusa com `nao_atende_cliente`, a área fica com a conversa
  # e a recusa vai para o log (decisão do Multifunnel, 15/10). Quem responde segue sendo a área, que pode falar.
  def destino_para(card)
    agente = responsavel(card.pipeline)
    # Responsável que não é mais área da caixa não tem como postar: conta como funil sem responsável. Um agente de área
    # não segue atendendo o funil de outra área.
    espelho = agente && Crm::Ai::Config.agent_inbox_for(inbox: @conversation.inbox, agent: agente)&.agent_bot
    return { bot: espelho, agente: agente } if espelho

    volta_para_a_porta
  end

  # Funil arquivado, fora da caixa ou com a IA do funil desligada não tem responsável: o mesmo critério do Abrir e do
  # destinos_para.
  def responsavel(pipeline)
    return unless Crm::Ai::Config.funil_de_destino?(pipeline, @conversation.inbox)

    Crm::Ai::Config.responsible_agent(inbox: @conversation.inbox, pipeline: pipeline)
  end

  # Só volta quem atende por um vínculo ativo nosso nesta caixa (a área): um robô externo com a conversa não é tirado.
  def volta_para_a_porta
    return unless VOLTA_PARA_A_PORTA.include?(@motivo) && dono_e_vinculo_da_caixa?

    vinculo = Autonomia::Agents::QuemResponde.porta_da_caixa(@conversation.inbox)
    return { bot: vinculo.agent_bot, agente: vinculo.agent } if vinculo&.agent

    Rails.logger.info("[crm][sync_dono] porta_sem_agente conversa=#{@conversation.id}")
    nil
  end

  # Inclui o vínculo removido: o espelho de uma área que saiu da caixa continua sendo nosso, e a conversa volta à porta.
  def dono_e_vinculo_da_caixa?
    Autonomia::Agents::AgentInbox.exists?(account_id: @account.id, inbox_id: @conversation.inbox_id,
                                          agent_bot_id: @conversation.assignee_agent_bot_id)
  end

  # A troca que segue um pedido do agente (Abrir) é registrada como ABRIR, com o transfer_id dele, qualquer que seja o
  # job que chegou primeiro: o Abrir também troca o foco, que agenda o seu próprio sync.
  def trocar(card, destino)
    de_bot = @conversation.ai_assignee
    pedido = pedido_do_agente(card)
    troca = { motivo: pedido ? ABRIR : @motivo, transfer_id: pedido&.payload&.dig('transfer_id') }
    passagem = Autonomia::Agents::PassarParaIa.call(conversation: @conversation, agent: destino[:agente], por: :crm,
                                                    motivo: troca[:motivo], origem: de_bot, transfer_id: troca[:transfer_id])
    return recusada(passagem) unless passagem.trocou?

    registrar_atividade(card, de_bot, destino, troca)
    Resultado.new(trocou: true, de_agent_bot_id: de_bot.id, para_agent_bot_id: destino[:bot].id,
                  autonomia_agent_id: destino[:agente].id, codigo: passagem.codigo, **troca)
  end

  def recusada(passagem)
    unless passagem.codigo == :ja_e_o_dono
      Rails.logger.info("[crm][sync_dono] passagem_recusada conversa=#{@conversation.id} codigo=#{passagem.codigo} motivo=#{@motivo}")
    end
    Resultado.new(trocou: false, motivo: @motivo, codigo: passagem.codigo)
  end

  def registrar_atividade(card, de_bot, destino, troca)
    Crm::ActivityLogger.new(
      card: card, actor: nil, event_type: EVENTO, conversation: @conversation,
      payload: { de_agent_bot_id: de_bot.id, para_agent_bot_id: destino[:bot].id, autonomia_agent_id: destino[:agente].id,
                 **troca }.compact
    ).perform
  end

  # O pedido do agente (Abrir) neste card, se é recente e ainda não virou troca desta conversa. O pedido que não virou
  # troca (havia pessoa, por exemplo) não vale para uma troca de horas depois.
  def pedido_do_agente(card)
    atividades = Crm::Activity.where(account_id: @account.id, conversation_id: @conversation.id)
    ultima_troca = atividades.where(event_type: EVENTO).maximum(:created_at)
    pedidos = atividades.where(card_id: card.id, event_type: Crm::Subjects::Abrir::EVENTO, created_at: JANELA_DO_PEDIDO.ago..)
    pedidos = pedidos.where('created_at > ?', ultima_troca) if ultima_troca
    pedidos.order(created_at: :desc, id: :desc).first
  end
end
