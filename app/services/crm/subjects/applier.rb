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

  # Vários assuntos numa mensagem (#1693). Os outros primeiro e o principal por último, que é quem a decisão registra:
  # o foco termina nele. Assunto aberto só entra na lista (a IA do CRM avalia); pedido novo cria o card só na
  # Automática e sem pessoa a respeitar (Sugerir e o respeito à pessoa valem para cada um). Devolve os atributos da
  # decisão e `tocados`: os cards que a mensagem tocou, o principal primeiro. "Nenhum assunto" não toca nada; vencida
  # por uma mais nova no meio, só os cards que ela já criou.
  def aplicar_varios(principal, outros)
    criados = []
    tocados = outros.filter_map { |escolha| tocar(escolha.opcao, escolha.titulo, criados) }
    resultado = aplicar(principal.opcao, principal.titulo)
    devolver_foco(resultado, criados) if criados.any?
    return resultado.merge(tocados: criados) if resultado[:state] == 'superseded'

    do_principal = card_do_principal(principal.opcao, resultado)
    resultado.merge(tocados: [do_principal, *tocados].compact.uniq(&:id))
  end

  private

  def tocar(opcao, titulo, criados)
    case opcao.tipo
    when :mesmo then @question.atual
    when :card then opcao.card
    when :novo then outro_pedido_novo(opcao.pipeline, titulo)&.tap { |card| criados << card }
    end
  end

  # O pedido novo que não é o principal: nasce sem levar o foco embora (o principal, aplicado depois, fica com ele).
  def outro_pedido_novo(pipeline, titulo)
    return if titulo.blank?

    resultado = nil
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      next if mensagem_mais_nova?
      next log_pedido_mantido(pipeline) if modo_efetivo('create', { pipeline: pipeline }) != 'auto'

      resultado = criar_ou_dar_nome(pipeline, titulo)
    end
    resultado[:card] if resultado&.dig(:state) == 'applied'
  end

  # Sugerir, ou a pessoa a respeitar: o pedido novo que não é o principal não vira card nem sugestão (só cabe uma
  # sugestão por conversa, e ela é do principal). Fica no log.
  def log_pedido_mantido(pipeline)
    Rails.logger.info("[crm][assunto] outro pedido novo mantido decisao=#{@decisao.id} funil=#{pipeline.id} modo=#{@mode}")
  end

  # Como no principal: o assunto atual ainda sem nome, no mesmo funil, ganha o nome em vez de nascer outro card.
  def criar_ou_dar_nome(pipeline, titulo)
    atual = @question.atual
    return dar_nome(atual.reload, titulo) if @question.atual_sem_nome? && atual.pipeline_id == pipeline.id

    criar(pipeline, titulo)
  end

  def card_do_principal(opcao, resultado)
    return if opcao.tipo == :sem_assunto || %w[applied kept suggested].exclude?(resultado[:state])

    resultado[:card]
  end

  # Um card novo que não é o principal nasce em foco (Crm::Cards::Creator). Se o foco ainda está num deles, volta para
  # o principal aplicado, ou para o assunto de antes quando o principal não mudou nada (mesmo assunto, sugestão, card
  # fechado, mensagem mais nova). Foco que já saiu deles (outra decisão, uma pessoa) não é mexido. Voltar o foco não
  # agenda avaliação: os cards da mensagem já vão na avaliação conjunta.
  def devolver_foco(resultado, criados)
    foco = resultado[:state] == 'applied' ? resultado[:card] : @question.atual
    return unless foco&.reload&.open?

    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      next unless criados.any? { |card| Crm::Assunto.atual?(card, @conversation) }

      Crm::Cards::Focus.new(account: @account, card: foco, conversation: @conversation, avaliar: false).perform
    end
  end

  def novo(pipeline, titulo)
    return no_card_do_aviso(pipeline, titulo) if card_do_aviso

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
    card_do_aviso&.card&.id == card.id ? renomear_o_do_aviso(card, titulo, pipeline) : dar_nome(card, titulo)
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
