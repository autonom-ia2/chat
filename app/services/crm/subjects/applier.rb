# Aplica a escolha de assunto (#1145) conforme o modo da caixa e devolve os atributos da decisão.
#
# Automática: dá nome ao assunto atual, volta a outro assunto aberto ou cria o card do pedido novo na primeira etapa do
# funil. Tudo dentro do lock da conversa (o mesmo do CardSyncer), conferindo de novo o que pode ter mudado enquanto a IA
# pensava: uma mensagem mais nova já decidida passa na frente; card que ganhou nome ou fechou não é mexido. O aviso em
# tempo real sai depois (Identifier).
# Sugerir: só grava a sugestão, com as mesmas checagens; a anterior que ninguém respondeu expira.
class Crm::Subjects::Applier
  # Decisões que não leram nada ou não chegaram ao fim: não passam na frente de uma mais antiga.
  SEM_EFEITO = %w[failed no_content no_quota].freeze

  def initialize(conversation:, question:, mode:, decisao:)
    @conversation = conversation
    @account = conversation.account
    @question = question
    @mode = mode
    @decisao = decisao
  end

  def aplicar(opcao, titulo)
    case opcao.tipo
    when :sem_assunto, :mesmo then { action: 'none', state: 'kept', card: @question.atual }
    when :card then decidir('focus', card: opcao.card)
    when :novo then novo(opcao.pipeline, titulo)
    end
  end

  private

  def novo(pipeline, titulo)
    atual = @question.atual
    if @question.atual_sem_nome? && atual.pipeline_id == pipeline.id
      decidir('rename', card: atual, pipeline: pipeline, title: titulo)
    else
      decidir('create', pipeline: pipeline, title: titulo)
    end
  end

  def decidir(action, **atributos)
    resultado = nil
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      resultado = if mensagem_mais_nova?
                    { state: 'superseded' }
                  elsif modo_efetivo(action, atributos) == 'suggest'
                    sugerir
                  else
                    executar(action, atributos)
                  end
    end
    atributos.merge(action: action).merge(resultado)
  end

  # Automática respeita a pessoa (#1260): trocar o assunto ou abrir card vira sugestão quando uma pessoa escolheu o
  # assunto há pouco, ou fechou/arquivou há pouco um card daquele funil nesta conversa. Dar nome não muda nada que a
  # pessoa fez (card nomeado por ela nunca é renomeado) e segue automático.
  def modo_efetivo(action, atributos)
    return @mode unless @mode == 'auto' && %w[focus create].include?(action)
    return 'suggest' if pessoa_escolheu_assunto?
    return 'suggest' if action == 'create' && pessoa_fechou_card?(atributos[:pipeline])

    @mode
  end

  def pessoa_escolheu_assunto?
    Crm::Cards::Focus.pessoa_escolheu?(account_id: @account.id, conversation_id: @conversation.id)
  end

  def pessoa_fechou_card?(pipeline)
    desde = Crm::Subjects::RESPEITO_AO_FECHAMENTO.ago
    vinculados = Crm::CardConversation.where(account_id: @account.id, conversation_id: @conversation.id).select(:card_id)
    do_funil = @account.crm_cards.where(pipeline_id: pipeline.id)
    cards = do_funil.where(conversation_id: @conversation.id).or(do_funil.where(id: vinculados))
    cards.where(closed_at: desde..).or(cards.where(status: :archived, updated_at: desde..)).exists?
  end

  def executar(action, atributos)
    case action
    when 'rename' then dar_nome(atributos[:card].reload, atributos[:title])
    when 'focus' then focar(atributos[:card].reload)
    when 'create' then criar(atributos[:pipeline], atributos[:title])
    end
  end

  # Marca já dentro do lock: duas sugestões da mesma conversa nunca ficam esperando ao mesmo tempo.
  def sugerir
    Crm::SubjectDecision.suggested.where(conversation_id: @conversation.id).update_all(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @decisao.update!(state: 'suggested')
    { state: 'suggested' }
  end

  # Outra mensagem do cliente, mais nova, já entrou na fila de decisão (mesmo ainda pensando): ela lê a conversa mais
  # recente e vale mais que esta.
  def mensagem_mais_nova?
    Crm::SubjectDecision.where(conversation_id: @conversation.id).where.not(id: @decisao.id).where.not(state: SEM_EFEITO)
                        .exists?(['message_id > ?', @decisao.message_id])
  end

  def dar_nome(card, titulo)
    return { state: 'kept', reason: 'card_mudou' } if !card.open? || Crm::Subjects::Naming.named?(card)

    card.update!(title: titulo, metadata: Crm::Subjects::Naming.metadata(card, 'ai'))
    Crm::ActivityLogger.new(card: card, actor: nil, event_type: 'update', payload: { title: titulo },
                            conversation: @conversation).perform
    { state: 'applied', card: card, evento: Events::Types::CRM_CARD_UPDATED }
  end

  def focar(card)
    return { state: 'kept', reason: 'card_mudou' } unless card.open?

    Crm::Subjects::Acoes.focar(conversation: @conversation, card: card)
    { state: 'applied', card: card, evento: Events::Types::CRM_CARD_UPDATED }
  end

  def criar(pipeline, titulo)
    card = Crm::Subjects::Acoes.criar(conversation: @conversation, pipeline: pipeline, titulo: titulo, source: 'ai')
    { state: 'applied', card: card, evento: Events::Types::CRM_CARD_CREATED }
  end
end
