# OUTRO CANAL (#1150, R13; decisão do Rodrigo em 12/10/2026). O cliente com card aberto que escreve por outra caixa: a
# conversa nova é ligada ao card aberto mais recente dele e entregue ao dono do card, sem passar pela triagem.
# Ex.: o João tem "Seguro do Onix" aberto com a Ana pelo WhatsApp e manda o documento por e-mail: o e-mail cai no mesmo
# card e vai para a Ana, em vez de nascer um card duplicado com outra pessoa.
#
# Quando age (do mais barato ao mais caro, e de novo sob a trava):
# - CRM ligado na instalação, a caixa nova com o CRM ligado e com algum funil ativo;
# - na mensagem do cliente que abriu a conversa (conversa que nós começamos, ou já em andamento, não entra);
# - a conversa ainda sem card, aberta ou pendente;
# - o card aberto do MESMO contato (outro cadastro com o mesmo telefone ou e-mail não vale: o merge de contato já leva
#   os cards), de OUTRA caixa (na mesma caixa vale a deduplicação de sempre), num funil ativo, com atividade nos
#   últimos JANELA_DE_ATIVIDADE (decisão do Rodrigo em 15/10: card parado há mais tempo não puxa a conversa). Mais de
#   um: o de atividade mais recente (a IA de assunto pode trocar o foco depois);
# - o card tem dono. Card sem dono: nada muda, a conversa segue a triagem.
#
# O que faz: liga a conversa ao card (vira o assunto atual dela; o funil do card passa a decidir quem a vê) e, se
# ninguém começou a atender (nenhuma resposta de pessoa), passa a conversa pelo motor de entrega (bot_handoff! →
# Crm::Entrega), numa gravação só: sai quem o rodízio nativo tinha posto e entra quem recebe. Dirigida ao dono
# (`dono:`) quando ele pode receber na caixa nova: é da conta, é membro dela e tem o funil do card nela (o mesmo critério
# do participante na saída da triagem, Crm::Access::TriageExit). Dono que não pode (decisão do Rodrigo em 15/10): liga
# do mesmo jeito, e o motor entrega para quem cuida do funil na caixa nova, pela regra de Atribuição se houver; o dono
# continua dono do card.
# Dono offline (decisão do Rodrigo em 15/10, "depende da regra de atribuição"): sem regra no funil, a conversa espera
# por ele, sem cair para outra pessoa; com regra, vale o que a regra manda (rodízio, pessoa fixa, convite, segurar até
# alguém entrar). Com o dono online e regra de convite, ele é convidado. Caixa com robô: o robô fazia a triagem (R12) e a
# R13 a pula; enquanto ninguém recebe, o robô segue respondendo.
# Quem já respondeu não perde a conversa: ela só fica ligada ao card. Quem está no nome sem ter respondido só sai se
# foi o rodízio nativo que o pôs (a triagem que a R13 pula), pelo registro de passagens (#1622, #1657): quem se
# atribuiu ou foi atribuído por uma pessoa fica.
#
# Roda dentro da sincronização do card (CardSyncer), sob a mesma trava (conversa e contato). Só nas contas com a flag
# `crm_outro_canal` (#1666); sem ela, nada muda.
class Crm::Conversations::OutroCanal
  MOTIVO = 'outro_canal'.freeze
  FLAG = 'crm_outro_canal'.freeze
  ATIVIDADE_SQL = 'COALESCE(crm_cards.last_activity_at, crm_cards.updated_at)'.freeze
  # Só puxa a conversa nova o card com atividade neste prazo (a mesma leitura de atividade da deduplicação).
  JANELA_DE_ATIVIDADE = 30.days

  def initialize(conversation:, message:)
    @conversation = conversation
    @message = message
    @account = conversation.account
  end

  # O card ligado, ou nil.
  def perform
    return unless candidata?

    card = Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform { ligar_e_entregar }
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED) if card
    card
  end

  private

  def candidata?
    ligada_na_conta? && @conversation.contact_id.present? && em_andamento? && abriu_a_conversa? && caixa_no_crm? && sem_card?
  end

  # Atrás da flag de conta `crm_outro_canal` (piloto: contas 1, 16 e 18; ligar: #1666). Sem ela, nada muda.
  def ligada_na_conta?
    @account.feature_enabled?(FLAG)
  end

  # Sob a trava, relendo: outra sincronização pode ter ligado ou criado um card nesse meio tempo.
  def ligar_e_entregar
    return unless em_andamento? && sem_card?

    card = card_travado
    return unless card&.owner && ligar(card)

    dono = dono_que_recebe(card)
    entregar(card, dono)
    registrar(card, dono)
    card
  end

  # Trava o card (depois da conversa e do contato, a ordem de sempre) e o relê: apagado ou fechado desde a consulta, não
  # liga; o dono e o acesso dele são lidos já sob a trava.
  def card_travado
    achado = card_aberto
    card = achado && @account.crm_cards.lock.find_by(id: achado.id)
    card if card&.open?
  end

  def em_andamento?
    @conversation.open? || @conversation.pending?
  end

  # A mensagem do cliente é a primeira da conversa (fora as de atividade): ele a abriu agora.
  def abriu_a_conversa?
    return false unless @message&.incoming?

    @conversation.messages.where.not(message_type: :activity).reorder(:id).pick(:id) == @message.id
  end

  # O mesmo critério do CardSyncer para a caixa com o CRM desligado, mais um funil ativo ligado a ela.
  def caixa_no_crm?
    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    return false if setting.present? && !setting.crm_enabled?

    @account.crm_pipeline_inboxes.joins(:pipeline).merge(Crm::Pipeline.active).exists?(inbox_id: @conversation.inbox_id)
  end

  def sem_card?
    Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).none?
  end

  def card_aberto
    @account.crm_cards.open.joins(:pipeline).merge(Crm::Pipeline.active)
            .where(contact_id: @conversation.contact_id)
            .where('crm_cards.inbox_id IS DISTINCT FROM ?', @conversation.inbox_id)
            .where("#{ATIVIDADE_SQL} >= ?", JANELA_DE_ATIVIDADE.ago)
            .order(Arel.sql("#{ATIVIDADE_SQL} DESC, crm_cards.id DESC"))
            .first
  end

  # O dono, se é pessoa da conta (não o usuário de integração), membro da caixa nova e tem o funil do card nela.
  def dono_que_recebe(card)
    dono = card.owner
    return if dono.nil?
    return unless AccountUser.exists?(account_id: @account.id, user_id: dono.id, integration: false)
    return unless @conversation.inbox.members.exists?(id: dono.id)

    dono if Crm::Access::CardScope.new(user: dono, account: @account).pipeline_allowed?(@conversation.inbox_id, card.pipeline_id)
  end

  # Card com conversa de outro contato vinculada: não liga, e a sincronização segue como antes.
  # Savepoint próprio: uma falha no meio do vínculo desfaz só o vínculo, e a sincronização segue como antes.
  def ligar(card)
    Conversation.transaction(requires_new: true) do
      Crm::Cards::ConversationLinker.new(card: card, conversation: @conversation, actor: nil).link
    end
  rescue ActiveRecord::RecordInvalid
    Rails.logger.warn("[crm][outro_canal] conversa=#{@conversation.id} card=#{card.id} nao_ligada=contato")
    nil
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error("[crm][outro_canal] vinculo_falhou conversa=#{@conversation.id} card=#{card.id} erro=#{e.class}")
    nil
  end

  # Já com o dono, ou com alguém que já respondeu: fica como está. `dono` nil (ele não pode receber na caixa nova): o
  # motor entrega para quem cuida do funil do card, como em qualquer entrega.
  # Savepoint próprio: uma falha da entrega desfaz só a entrega; a conversa segue ligada e a sincronização continua.
  def entregar(card, dono)
    return if dono && @conversation.assignee_id == dono.id
    return if pessoa_respondeu?
    return if @conversation.assignee_id.present? && !posta_pelo_rodizio?

    Conversation.transaction(requires_new: true) do
      @conversation.bot_handoff!(dispatch_event: false, motivo: MOTIVO, release_assignee: true, dono: dono)
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error("[crm][outro_canal] entrega_falhou conversa=#{@conversation.id} card=#{card.id} erro=#{e.class}")
    @conversation.reload
  end

  def pessoa_respondeu?
    @conversation.messages.outgoing.exists?(sender_type: 'User')
  end

  # Quem está no nome foi posto pelo rodízio nativo (#1657): a caixa tem o rodízio e a passagem em aberto para essa
  # pessoa (o registro de passagens, #1622) não foi pedida por ninguém, isto é, pelo sistema. Pedida por uma pessoa
  # (autoatribuição, "Atribuir a"), ou sem passagem registrada: fica com quem está, mesmo sem ter respondido.
  def posta_pelo_rodizio?
    return false unless @conversation.inbox.enable_auto_assignment?

    passagem = Crm::Passagens.ultima_aberta(@conversation)
    passagem.present? && passagem.para_type == 'User' && passagem.para_id == @conversation.assignee_id &&
      passagem.pedida_por_type.nil?
  end

  # Só ids (nunca texto do cliente).
  def registrar(card, dono)
    Rails.logger.info(
      "[crm][outro_canal] conversa=#{@conversation.id} conta=#{@account.id} card=#{card.id} dono=#{card.owner_id} " \
      "dirigida=#{dono ? 'sim' : 'nao'} atendente=#{@conversation.assignee_id || '-'}"
    )
  end
end
