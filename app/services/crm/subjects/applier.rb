# Aplica a escolha de assunto (#1145) conforme o modo da caixa e devolve os atributos da decisão.
#
# Automática: dá nome ao assunto atual, volta a outro assunto aberto ou cria o card do pedido novo na primeira etapa do
# funil. Tudo dentro do lock da conversa (o mesmo do CardSyncer), conferindo de novo o que pode ter mudado enquanto a IA
# pensava: uma mensagem mais nova já decidida passa na frente; card que ganhou nome ou fechou não é mexido. O aviso em
# tempo real sai depois (Identifier).
# Sugerir: só grava a sugestão, com as mesmas checagens; a anterior que ninguém respondeu expira.
class Crm::Subjects::Applier
  include Crm::Subjects::VariosAssuntos

  # Decisões que não leram nada ou não chegaram ao fim: não passam na frente de uma mais antiga.
  SEM_EFEITO = %w[failed no_content no_quota].freeze

  # anterior: o retrato da decisão reaberta pelo WhatsApp Híbrido (#1638), ou nil.
  def initialize(conversation:, question:, mode:, decisao:, anterior: nil)
    @conversation = conversation
    @account = conversation.account
    @question = question
    @mode = mode
    @decisao = decisao
    @anterior = anterior
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
    return no_card_do_aviso(pipeline, titulo) if card_do_aviso

    atual = @question.atual
    mesmo_funil = @question.atual_sem_nome? && atual.pipeline_id == pipeline.id
    @chegada = card_da_chegada(pipeline) unless mesmo_funil
    if mesmo_funil || @chegada
      decidir('rename', card: atual, pipeline: pipeline, title: titulo)
    else
      decidir('create', pipeline: pipeline, title: titulo)
    end
  end

  # C36 (#1711): na caixa com card ao chegar, o cliente sem card aberto ganha um card sem nome no funil padrão antes de
  # a IA de assunto decidir. Com a flag `crm_avaliar_toda_mensagem` e a caixa em Automática, o pedido de outro funil
  # leva esse card para a 1ª etapa do funil do assunto e lhe dá o nome, em vez de deixar um card vazio para trás. Só o
  # card que o sistema criou na chegada (crm_auto_sync), desta conversa, sem nome, que nunca mudou de etapa e em que
  # nenhuma pessoa mexeu, e que pode ir para aquele funil (com o dono). O resto segue como antes: nasce outro card.
  # Respeita a pessoa como a criação (#1260): quando criar viraria sugestão, o card da chegada não é tocado.
  def card_da_chegada(pipeline)
    return unless modo_efetivo('create', { pipeline: pipeline }) == 'auto'

    Crm::Subjects::CardDaChegada.de(conversation: @conversation, card: @question.atual, mode: @mode, pipeline: pipeline)
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
    when 'rename' then renomear(atributos[:card].reload, atributos[:title], atributos[:pipeline])
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

  # #1638: o card que a IA criou ou nomeou em cima do aviso, numa decisão reaberta (Crm::Subjects::CardDoAviso). Card
  # fechado depois do aviso não entra: o assunto real segue o caminho de sempre.
  def card_do_aviso
    return @card_do_aviso if defined?(@card_do_aviso)

    @card_do_aviso = Crm::Subjects::CardDoAviso.de(account: @account, anterior: @anterior)
  end

  # Mexido por uma pessoa, funil fora do acesso ou troca de funil com a caixa em Sugerir: o card fica como está e nada
  # novo nasce; só o log registra. Mesmo assunto: nada muda.
  def no_card_do_aviso(pipeline, titulo)
    aviso = card_do_aviso
    if aviso.pessoa_mexeu? || !aviso.pode_ir_para?(pipeline) || (aviso.card.pipeline_id != pipeline.id && @mode != 'auto')
      Rails.logger.info("[crm][assunto] card do aviso mantido decisao=#{@decisao.id} card=#{aviso.card.id}")
      return { action: 'none', state: 'kept', reason: 'card_do_aviso_mantido', card: aviso.card }
    end
    return { action: 'none', state: 'kept', card: aviso.card } if aviso.mesmo_assunto?(pipeline, titulo)

    decidir('rename', card: aviso.card, pipeline: pipeline, title: titulo)
  end

  def renomear(card, titulo, pipeline)
    return renomear_o_do_aviso(card, titulo, pipeline) if card_do_aviso&.card&.id == card.id
    return adotar_a_chegada(card, titulo, pipeline) if @chegada&.card&.id == card.id

    dar_nome(card, titulo)
  end

  # C36: confere de novo dentro do lock (a pessoa pode ter mexido enquanto a IA pensava), leva o card ao funil do
  # assunto, dá o nome e agenda a IA do CRM nele, já no funil novo. Ele já é o assunto atual: o foco não muda. Se ele
  # mudou no meio-tempo, o pedido não se perde: segue o caminho da criação, com a mesma regra de respeito à pessoa
  # (#1260), relida aqui dentro da trava.
  def adotar_a_chegada(card, titulo, pipeline)
    unless @chegada.recarregar.adotavel?(pipeline) && modo_efetivo('create', { pipeline: pipeline }) == 'auto'
      return criar_no_lugar_da_chegada(pipeline, titulo)
    end

    @chegada.mover_para(pipeline)
    resultado = dar_nome_da_ia(card.reload, titulo)
    Crm::Ai::Observer.new(card: card).schedule_evaluation
    resultado
  end

  def criar_no_lugar_da_chegada(pipeline, titulo)
    resultado = modo_efetivo('create', { pipeline: pipeline }) == 'auto' ? criar(pipeline, titulo) : sugerir
    { action: 'create', card: nil }.merge(resultado)
  end

  # Leva ao funil do assunto real (se for outro), dá o nome novo e o card volta a ser o assunto atual, a menos que a
  # pessoa tenha escolhido outro há pouco.
  def renomear_o_do_aviso(card, titulo, pipeline)
    return { state: 'kept', reason: 'card_mudou' } unless card.open?
    # De novo dentro do lock: a pessoa pode ter mexido no card enquanto a IA pensava.
    return { state: 'kept', reason: 'card_do_aviso_mantido' } if card_do_aviso.recarregar.pessoa_mexeu?

    card_do_aviso.mover_para(pipeline)
    resultado = dar_nome_da_ia(card.reload, titulo)
    Crm::Subjects::Acoes.focar(conversation: @conversation, card: card) unless card == @question.atual || pessoa_escolheu_assunto?
    resultado
  end

  def dar_nome(card, titulo)
    return { state: 'kept', reason: 'card_mudou' } if !card.open? || Crm::Subjects::Naming.named?(card)

    dar_nome_da_ia(card, titulo)
  end

  def dar_nome_da_ia(card, titulo)
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
