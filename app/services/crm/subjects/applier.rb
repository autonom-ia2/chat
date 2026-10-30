# Aplica a escolha de assunto (#1145) conforme o modo da caixa e devolve os atributos da decisão.
#
# Automática: dá nome ao assunto atual, volta a outro assunto aberto ou cria o card do pedido novo na primeira etapa do
# funil. Tudo dentro do lock da conversa (o mesmo do CardSyncer), conferindo de novo o que pode ter mudado enquanto a IA
# pensava: uma mensagem mais nova já decidida passa na frente; card que ganhou nome ou fechou não é mexido. O aviso em
# tempo real sai depois (Identifier).
# Sugerir: só grava a sugestão, com as mesmas checagens; a anterior que ninguém respondeu expira.
# Coluna do card novo (#1910, Crm::Subjects::Etapa): o card criado, o da chegada levado a outro funil (C36) e o da
# chegada sem nome do mesmo funil vão para a etapa escolhida. As automações de entrada dela rodam depois da trava.
# Automática que vira sugestão por respeito à pessoa (#1260) deixa a etapa de lado: o card aceito nasce na 1ª etapa,
# como no Sugerir (decisão do Rodrigo, 19/10: o Sugerir fica fora).
# Nome genérico (#2163, Crm::Subjects::NomeProvisorio): o nome que o modelo disse ser genérico leva a marca de provisório;
# "o mesmo assunto" com nome refina esse nome uma vez, ou dá nome ao card sem nome que já carregava um pedido. Esse card
# não é renomeado pelo pedido novo do mesmo funil: o pedido novo vira outro card.
class Crm::Subjects::Applier # rubocop:disable Metrics/ClassLength -- o nome provisório (#2163) mora junto do dar nome
  include Crm::Subjects::VariosAssuntos

  # Decisões que não leram nada ou não chegaram ao fim: não passam na frente de uma mais antiga.
  SEM_EFEITO = %w[failed no_content no_quota].freeze
  # #2084: o contato saiu do funil enquanto a IA pensava; nada muda.
  SAIU_DO_FUNIL = 'fora_do_funil'.freeze

  # anterior: o retrato da decisão reaberta pelo WhatsApp Híbrido (#1638), ou nil.
  def initialize(conversation:, question:, mode:, decisao:, anterior: nil)
    @conversation = conversation
    @account = conversation.account
    @question = question
    @mode = mode
    @decisao = decisao
    @anterior = anterior
  end

  # etapa: a chave da etapa escolhida para o pedido novo (#1910), ou nil. Assunto encerrado (F2): nada muda, nem dentro
  # da trava (Crm::Subjects::Encerrado.decisao). generico (#2163): o modelo disse que o nome é genérico.
  def aplicar(opcao, titulo, etapa = nil, generico: false)
    case opcao.tipo
    when :sem_assunto then { action: 'none', state: 'kept', card: @question.atual }
    when :mesmo then mesmo(titulo, generico)
    when Crm::Subjects::Encerrado::TIPO then Crm::Subjects::Encerrado.decisao(opcao.card)
    when :card then decidir('focus', card: opcao.card)
    when :novo then novo(opcao.pipeline, titulo, @question.etapa(opcao.pipeline, etapa), generico: generico)
    end
  end

  # A dúvida do modelo maior: nada muda, a menos que traga a sugestão de pedido novo (#2162, Crm::Subjects::DuvidaSugerida).
  # Aí vira sugestão de criar o card, em qualquer modo: só uma pessoa cria. Fica a dúvida quando a conversa já tem um
  # card sem nome e sem pedido (ele recebe o pedido quando ficar claro) e, conferido dentro da trava, quando outra
  # sugestão espera uma pessoa (a dúvida, sinal mais fraco, não derruba a sugestão clara) ou a pessoa ignorou há pouco a
  # mesma (#1260). Uma mensagem mais nova passa na frente.
  def duvida(em_duvida)
    sugestao = em_duvida[:sugestao]
    base = em_duvida.except(:sugestao)
    return base if sugestao.nil? || (@question.atual_sem_nome? && !@question.atual_carrega_pedido?)

    resultado = nil
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      resultado = if mensagem_mais_nova?
                    { state: 'superseded' }
                  elsif sugestao_bloqueada?(sugestao[:pipeline])
                    {}
                  else
                    sugerir
                  end
    end
    return base if resultado.empty?

    base.merge(action: 'create', card: nil, pipeline: sugestao[:pipeline], title: sugestao[:title],
               reason: Crm::Subjects::DuvidaSugerida::MOTIVO).merge(resultado)
  end

  private

  # "O mesmo assunto" (#2163, com a flag): marca que o card carrega um pedido (em qualquer modo: o pedido novo do mesmo
  # funil não apaga o primeiro, nem como sugestão) e, com nome do modelo, refina o nome genérico ou dá nome ao card sem
  # nome que já carregava o pedido. Dar o nome, só na Automática (Question#atual_nomeavel?): no Sugerir o nome que a
  # pessoa aceitou é dela. Sem a flag, nada muda.
  def mesmo(titulo, generico)
    atual = @question.atual
    return { action: 'none', state: 'kept', card: atual } unless Crm::Subjects::NomeProvisorio.ligada?(@account)

    mantido = { action: 'none', state: 'kept', card: atual, reason: Crm::Subjects::NomeProvisorio::MESMO_ASSUNTO }
    return mantido unless titulo.present? && @question.atual_nomeavel?

    decidir('rename', card: atual, pipeline: atual.pipeline, title: titulo, generico: generico)
  end

  def novo(pipeline, titulo, etapa, generico: false)
    return no_card_do_aviso(pipeline, titulo, generico) if card_do_aviso

    atributos = { pipeline: pipeline, title: titulo, etapa: etapa, generico: generico }
    if mesmo_funil_sem_nome?(pipeline)
      # #2163: o card sem nome que já carregava um pedido não é renomeado pelo segundo: o pedido novo ganha outro card.
      return criar_no_lugar_do_que_tinha_pedido(atributos) if @question.atual_carrega_pedido?

      return decidir('rename', card: @question.atual, **atributos)
    end

    @chegada = card_da_chegada(pipeline)
    @chegada ? decidir('rename', card: @question.atual, **atributos) : decidir('create', **atributos)
  end

  def mesmo_funil_sem_nome?(pipeline)
    @question.atual_sem_nome? && @question.atual.pipeline_id == pipeline.id
  end

  def criar_no_lugar_do_que_tinha_pedido(atributos)
    resultado = decidir('create', **atributos)
    resultado[:state] == 'applied' ? resultado.merge(reason: Crm::Subjects::NomeProvisorio::JA_TINHA_PEDIDO) : resultado
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
    @entradas = []
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      resultado = if mensagem_mais_nova?
                    { state: 'superseded' }
                  elsif saiu_do_funil?
                    { state: 'kept', reason: SAIU_DO_FUNIL }
                  elsif modo_efetivo(action, atributos) == 'suggest'
                    sugerir
                  else
                    executar(action, atributos)
                  end
    end
    entrar_nas_etapas
    atributos.except(:etapa, :generico).merge(action: action).merge(resultado)
  end

  # #1910: as automações de entrada das etapas escolhidas, fora da trava da conversa.
  def entrar_nas_etapas
    entradas = @entradas.to_a
    @entradas = []
    entradas.each { |card, etapa| Crm::Subjects::Etapa.entrar(card, etapa) }
  end

  def entrar_depois(card, etapa)
    (@entradas ||= []) << [card, etapa] if etapa
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
    arquivados = cards.where(status: :archived, updated_at: desde..).where.not(id: arquivados_pela_ia(desde))
    fechados = cards.where(closed_at: desde..)
    # IA entende a conversa F3: o card que a IA fechou (o "adiou", por exemplo) também não é fechamento de uma pessoa.
    fechados = fechados.where.not(id: Crm::Ai::FecharCard.fechados_pela_ia(@account, desde)) if Crm::Ai::FecharCard.ligada?(@account)
    fechados.or(arquivados).exists?
  end

  # O card que a IA de etapa tirou do funil como "não é negócio" (#1922) não é fechamento de uma pessoa: o cliente que
  # volta ganha card, não só sugestão.
  def arquivados_pela_ia(desde)
    Crm::Ai::NaoENegocio.arquivamentos(@account.id).where(created_at: desde..).select(:card_id)
  end

  def executar(action, atributos)
    generico = atributos[:generico] == true
    case action
    when 'rename' then renomear(atributos[:card].reload, atributos[:title], atributos[:pipeline], atributos[:etapa], generico: generico)
    when 'focus' then focar(atributos[:card].reload)
    when 'create' then criar(atributos[:pipeline], atributos[:title], atributos[:etapa], generico: generico)
    end
  end

  # #2162, dentro da trava: outra sugestão espera uma pessoa, ou ela ignorou há pouco a de criar card neste funil. Como
  # no #1260, só por RESPEITO_AO_FECHAMENTO: uma sugestão esquecida não prende a conversa para sempre.
  # O contato que saiu do funil (#2084) também bloqueia: nenhuma sugestão fica esperando uma pessoa.
  def sugestao_bloqueada?(pipeline)
    return true if saiu_do_funil?

    recentes = Crm::SubjectDecision.where(conversation_id: @conversation.id, updated_at: Crm::Subjects::RESPEITO_AO_FECHAMENTO.ago..)
                                   .where.not(id: @decisao.id)
    recentes.suggested.exists? || recentes.exists?(state: 'dismissed', action: %w[create rename], pipeline_id: pipeline.id)
  end

  # Marca já dentro do lock: duas sugestões da mesma conversa nunca ficam esperando ao mesmo tempo.
  def sugerir
    Crm::SubjectDecision.suggested.where(conversation_id: @conversation.id).update_all(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    @decisao.update!(state: 'suggested')
    { state: 'suggested' }
  end

  # #2084: a pessoa tirou o contato do funil enquanto a IA pensava (o Identifier conferiu antes de perguntar). O SyncLock
  # trava a linha do contato, a mesma que o Crm::Relacao::Marcar grava: lida aqui dentro, a relação é a final.
  def saiu_do_funil?
    Crm::Relacao.fora_do_funil?(@account.contacts.find_by(id: @conversation.contact_id))
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
  def no_card_do_aviso(pipeline, titulo, generico = nil)
    aviso = card_do_aviso
    if aviso.pessoa_mexeu? || !aviso.pode_ir_para?(pipeline) || (aviso.card.pipeline_id != pipeline.id && @mode != 'auto')
      Rails.logger.info("[crm][assunto] card do aviso mantido decisao=#{@decisao.id} card=#{aviso.card.id}")
      return { action: 'none', state: 'kept', reason: 'card_do_aviso_mantido', card: aviso.card }
    end
    return { action: 'none', state: 'kept', card: aviso.card } if aviso.mesmo_assunto?(pipeline, titulo)

    decidir('rename', card: aviso.card, pipeline: pipeline, title: titulo, generico: generico)
  end

  def renomear(card, titulo, pipeline, etapa = nil, generico: false)
    return renomear_o_do_aviso(card, titulo, pipeline, generico: generico) if card_do_aviso&.card&.id == card.id
    return adotar_a_chegada(card, titulo, pipeline, etapa, generico: generico) if @chegada&.card&.id == card.id

    dar_nome_e_levar(card, titulo, etapa, generico: generico)
  end

  # #1910: o card da chegada sem nome, no mesmo funil do pedido, ganha o nome e vai para a etapa escolhida. As guardas
  # do C36 (criado na chegada, nunca mudou de etapa, sem mexida de pessoa) são lidas antes do nome, que muda o card.
  # Respeita a pessoa como a criação (#1260): quando criar viraria sugestão, o card só ganha o nome e fica onde está.
  def dar_nome_e_levar(card, titulo, etapa, generico: false)
    chegada = Crm::Subjects::CardDaChegada.no_funil(conversation: @conversation, card: card) if levar_a_etapa?(card, etapa)
    resultado = dar_nome(card, titulo, generico: generico)
    return resultado unless chegada && resultado[:state] == 'applied'

    chegada.mover_para(card.pipeline, etapa)
    entrar_depois(card, etapa)
    resultado
  end

  def levar_a_etapa?(card, etapa)
    etapa.present? && modo_efetivo('create', { pipeline: card.pipeline }) == 'auto'
  end

  # C36: confere de novo dentro do lock (a pessoa pode ter mexido enquanto a IA pensava), leva o card ao funil do
  # assunto, dá o nome e agenda a IA do CRM nele, já no funil novo. Ele já é o assunto atual: o foco não muda. Se ele
  # mudou no meio-tempo, o pedido não se perde: segue o caminho da criação, com a mesma regra de respeito à pessoa
  # (#1260), relida aqui dentro da trava.
  def adotar_a_chegada(card, titulo, pipeline, etapa = nil, generico: false)
    unless @chegada.recarregar.adotavel?(pipeline) && modo_efetivo('create', { pipeline: pipeline }) == 'auto'
      return criar_no_lugar_da_chegada(pipeline, titulo, etapa, generico: generico)
    end

    @chegada.mover_para(pipeline, etapa)
    entrar_depois(card, etapa)
    resultado = dar_nome_da_ia(card.reload, titulo, generico: generico)
    Crm::Ai::Observer.new(card: card).schedule_evaluation
    resultado
  end

  def criar_no_lugar_da_chegada(pipeline, titulo, etapa, generico: false)
    resultado = modo_efetivo('create', { pipeline: pipeline }) == 'auto' ? criar(pipeline, titulo, etapa, generico: generico) : sugerir
    { action: 'create', card: nil }.merge(resultado)
  end

  # Leva ao funil do assunto real (se for outro), dá o nome novo e o card volta a ser o assunto atual, a menos que a
  # pessoa tenha escolhido outro há pouco.
  def renomear_o_do_aviso(card, titulo, pipeline, generico: false)
    return { state: 'kept', reason: 'card_mudou' } unless card.open?
    # De novo dentro do lock: a pessoa pode ter mexido no card enquanto a IA pensava.
    return { state: 'kept', reason: 'card_do_aviso_mantido' } if card_do_aviso.recarregar.pessoa_mexeu?

    card_do_aviso.mover_para(pipeline)
    resultado = dar_nome_da_ia(card.reload, titulo, generico: generico)
    Crm::Subjects::Acoes.focar(conversation: @conversation, card: card) unless card == @question.atual || pessoa_escolheu_assunto?
    resultado
  end

  # O nome genérico (#2163) é refinado uma vez: só quando o modelo deu um nome específico e diferente; senão fica como está.
  def dar_nome(card, titulo, generico: false)
    return { state: 'kept', reason: 'card_mudou' } unless card.open?
    return refinar(card, titulo, generico) if Crm::Subjects::NomeProvisorio.refinavel?(card)
    return { state: 'kept', reason: 'card_mudou' } if Crm::Subjects::Naming.named?(card)

    dar_nome_da_ia(card, titulo, generico: generico)
  end

  def refinar(card, titulo, generico)
    sem_nome_novo = { action: 'none', state: 'kept', title: nil, reason: Crm::Subjects::NomeProvisorio::MESMO_ASSUNTO }
    return sem_nome_novo if generico || titulo == card.title

    dar_nome_da_ia(card, titulo).merge(reason: Crm::Subjects::NomeProvisorio::REFINADO)
  end

  # generico (#2163): o nome leva a marca de provisório, só com a flag.
  def dar_nome_da_ia(card, titulo, generico: false)
    provisorio = generico && Crm::Subjects::NomeProvisorio.ligada?(@account)
    card.update!(title: titulo, metadata: Crm::Subjects::Naming.metadata(card, 'ai', titulo: titulo, provisorio: provisorio))
    Crm::ActivityLogger.new(card: card, actor: nil, event_type: 'update', payload: { title: titulo },
                            conversation: @conversation).perform
    { state: 'applied', card: card, evento: Events::Types::CRM_CARD_UPDATED }
  end

  def focar(card)
    return { state: 'kept', reason: 'card_mudou' } unless card.open?

    Crm::Subjects::Acoes.focar(conversation: @conversation, card: card)
    { state: 'applied', card: card, evento: Events::Types::CRM_CARD_UPDATED }
  end

  def criar(pipeline, titulo, etapa = nil, generico: false)
    provisorio = generico && Crm::Subjects::NomeProvisorio.ligada?(@account)
    card = Crm::Subjects::Acoes.criar(conversation: @conversation, pipeline: pipeline, titulo: titulo, source: 'ai', etapa: etapa,
                                      provisorio: provisorio)
    entrar_depois(card, etapa)
    { state: 'applied', card: card, evento: Events::Types::CRM_CARD_CREATED }
  end
end
