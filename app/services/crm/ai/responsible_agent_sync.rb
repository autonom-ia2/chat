# Entrega a conversa ao agente de IA responsável pelo assunto em atendimento (#1447, contrato com Agentes IA #1433).
#
# Quem atende é o robô da conversa (ai_assignee). Quando o assunto em atendimento é de um funil que, naquela caixa,
# tem um agente responsável (Crm::InboxAiAgent), o espelho (AgentBot) do vínculo de área dele passa a ser o
# ai_assignee, pelo mesmo AssignmentService da atribuição manual. Roda no job, no lock da conversa, e confere tudo de
# novo com a conversa relida. Nada troca quando:
# - uma pessoa está atribuída, ou a conversa espera uma pessoa (passagem do robô);
# - nenhum robô atende a conversa agora (sem ai_assignee): entregar a um robô seria tirá-la da fila de pessoas;
# - a conversa está resolvida ou adiada e a troca não veio do pedido do agente: entregar a um robô a reabriria;
# - o responsável já é quem atende.
# Funil arquivado, fora da caixa, com a IA do funil desligada, cujo responsável está parado ou não é mais área da caixa,
# ou conta sem a Fase 2 dos Agentes (Crm::Ai::Config.areas_ligadas?): conta como funil sem responsável. Sem a Fase 2,
# então, o sync só devolve à porta, nunca entrega a uma área.
#
# A porta (o robô ativo da caixa) só recebe a conversa de volta quando o próprio card em atendimento passa para um
# funil sem responsável (motivo PIPELINE). Troca de foco ou pedido do agente nunca devolvem à porta sozinhos.
#
# A troca fica na atividade do card (ai_agent_changed), com o transfer_id do pedido do agente (Crm::Subjects::Abrir)
# quando houver. Depois do commit sai o evento EVENTO_TROCA (ActiveSupport::Notifications) com
# { conversation:, from_bot:, to_bot:, agent:, transfer_id:, motivo: } — o contrato com o Agentes IA, que assina o
# evento para enfileirar a resposta do agente de destino, para a frase da origem sair antes.
class Crm::Ai::ResponsibleAgentSync
  PIPELINE = 'pipeline'.freeze
  FOCO = 'foco'.freeze
  ABRIR = 'abrir'.freeze
  MOTIVOS = [PIPELINE, FOCO, ABRIR].freeze
  EVENTO = 'ai_agent_changed'.freeze
  EVENTO_TROCA = 'crm.ai.responsible_agent_changed'.freeze
  # O pedido do agente (Abrir) vira troca no job logo em seguida; mais velho que isto, o transfer_id não é dele.
  JANELA_DO_PEDIDO = 10.minutes

  Resultado = Struct.new(:trocou, :de_agent_bot_id, :para_agent_bot_id, :autonomia_agent_id, :transfer_id, :motivo,
                         :evento, keyword_init: true)

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
    publicar(resultado) if resultado.trocou
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

  # Resolvida ou adiada só conta no pedido do agente (ABRIR): ele está atendendo agora, e a resposta dele reabre a
  # conversa de qualquer jeito. Troca de foco ou de funil numa conversa parada não a reabre.
  def conversa_com_robo?
    (@motivo == ABRIR || @conversation.open? || @conversation.pending?) && @conversation.assignee_id.blank? &&
      !@conversation.bot_handoff_waiting? && @conversation.ai_assignee.is_a?(AgentBot)
  end

  # A regra única de "qual funil manda" (#1606, Crm::Assunto.funil_atual), relida sob a trava.
  def card_em_atendimento
    card = Crm::Assunto.funil_atual(@conversation)
    return if card.nil?
    return if @motivo == PIPELINE && card.id != @card_id.to_i

    card
  end

  # { bot:, agente: } para quem a conversa vai, ou nil quando nada troca.
  def destino_para(card)
    porta = @conversation.inbox_agent_bot
    agente = responsavel(card.pipeline)
    return volta_para_a_porta(porta) if agente.nil?

    espelho = Crm::Ai::Config.agent_inbox_for(inbox: @conversation.inbox, agent: agente)&.agent_bot
    # Responsável que não é mais área da caixa não tem como postar: conta como funil sem responsável. Um agente de área
    # não segue atendendo o funil de outra área.
    return volta_para_a_porta(porta) if espelho.nil?

    { bot: espelho, agente: agente }
  end

  # Funil arquivado, fora da caixa ou com a IA do funil desligada não tem responsável: o mesmo critério do Abrir e do
  # destinos_para.
  def responsavel(pipeline)
    return unless Crm::Ai::Config.funil_de_destino?(pipeline, @conversation.inbox)

    Crm::Ai::Config.responsible_agent(inbox: @conversation.inbox, pipeline: pipeline)
  end

  # Sem responsável: só o card em atendimento mudando de funil devolve à porta.
  def volta_para_a_porta(porta)
    { bot: porta, agente: nil } if porta && @motivo == PIPELINE
  end

  # A troca que segue um pedido do agente (Abrir) é registrada como ABRIR, com o transfer_id dele, qualquer que seja o
  # job que chegou primeiro: o Abrir também troca o foco, que agenda o seu próprio sync.
  def trocar(card, destino)
    de_bot = @conversation.ai_assignee
    Conversations::AssignmentService.new(conversation: @conversation, assignee_id: destino[:bot].id, assignee_type: 'AgentBot').perform
    pedido = pedido_do_agente(card)
    troca = { motivo: pedido ? ABRIR : @motivo, transfer_id: pedido&.payload&.dig('transfer_id') }
    Crm::ActivityLogger.new(
      card: card, actor: nil, event_type: EVENTO, conversation: @conversation,
      payload: { de_agent_bot_id: de_bot.id, para_agent_bot_id: destino[:bot].id, autonomia_agent_id: destino[:agente]&.id,
                 **troca }.compact
    ).perform
    Resultado.new(trocou: true, de_agent_bot_id: de_bot.id, para_agent_bot_id: destino[:bot].id,
                  autonomia_agent_id: destino[:agente]&.id, **troca,
                  evento: { conversation: @conversation, from_bot: de_bot, to_bot: destino[:bot], agent: destino[:agente], **troca })
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

  def publicar(resultado)
    ActiveRecord.after_all_transactions_commit { ActiveSupport::Notifications.instrument(EVENTO_TROCA, resultado.evento) }
  end
end
