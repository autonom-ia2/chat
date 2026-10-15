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
#   os cards), de OUTRA caixa (na mesma caixa vale a deduplicação de sempre), num funil ativo. Mais de um: o de atividade
#   mais recente (a IA de assunto pode trocar o foco depois);
# - o dono desse card pode receber na caixa nova: é da conta, é membro da caixa e tem o funil do card nela (o mesmo
#   critério do participante na saída da triagem, Crm::Access::TriageExit). Card sem dono, ou dono que não pode: nada
#   muda, a conversa segue a triagem.
#
# O que faz: liga a conversa ao card (vira o assunto atual dela; o funil do card passa a decidir quem a vê) e, se
# ninguém começou a atender (nenhuma resposta de pessoa), passa a conversa pelo motor de entrega dirigida ao dono
# (bot_handoff! → Crm::Entrega com `dono:`), numa gravação só: sai quem o rodízio nativo tinha posto e entra o dono.
# Dono offline ou regra de convite: o motor segura ou convida, como faz para a pessoa fixa da Atribuição. Caixa com robô:
# o robô fazia a triagem (R12) e a R13 a pula; com o dono fora, o robô segue respondendo à espera dele.
# Quem já respondeu não perde a conversa: ela só fica ligada ao card. Numa caixa com o rodízio nativo, quem está no
# nome sem ter respondido (o rodízio atribui na criação, antes desta sincronização) sai: é a triagem que a R13 pula.
# Sem o rodízio, quem está no nome foi posto por uma pessoa ou automação e fica.
#
# Roda dentro da sincronização do card (CardSyncer), sob a mesma trava (conversa e contato).
class Crm::Conversations::OutroCanal
  MOTIVO = 'outro_canal'.freeze
  ATIVIDADE_SQL = 'COALESCE(crm_cards.last_activity_at, crm_cards.updated_at)'.freeze

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
    @conversation.contact_id.present? && em_andamento? && abriu_a_conversa? && caixa_no_crm? && sem_card?
  end

  # Sob a trava, relendo: outra sincronização pode ter ligado ou criado um card nesse meio tempo.
  def ligar_e_entregar
    return unless em_andamento? && sem_card?

    card = card_travado
    dono = card && dono_que_recebe(card)
    return unless dono && ligar(card)

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
  def ligar(card)
    Crm::Cards::ConversationLinker.new(card: card, conversation: @conversation, actor: nil).link
  rescue ActiveRecord::RecordInvalid
    Rails.logger.warn("[crm][outro_canal] conversa=#{@conversation.id} card=#{card.id} nao_ligada=contato")
    nil
  end

  # Já com o dono, ou com alguém que já respondeu: fica como está.
  # O dono precisa estar na fila de quem cuida, a mesma que o motor usa (já com o card ligado): fora dela, a conversa
  # fica só ligada ao card, e não vai para outra pessoa da fila no lugar dele.
  # Savepoint próprio: uma falha da entrega desfaz só a entrega; a conversa segue ligada e a sincronização continua.
  def entregar(card, dono)
    return if @conversation.assignee_id == dono.id
    return if pessoa_respondeu? || atribuida_por_alguem?
    return unless Crm::Entrega::QuemCuida.new(conversation: @conversation, card: card).pessoas.include?(dono)

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

  # Com alguém no nome numa caixa sem o rodízio nativo, quem pôs foi uma pessoa ou uma automação, não a triagem: fica.
  def atribuida_por_alguem?
    @conversation.assignee_id.present? && !@conversation.inbox.enable_auto_assignment?
  end

  # Só ids (nunca texto do cliente).
  def registrar(card, dono)
    Rails.logger.info(
      "[crm][outro_canal] conversa=#{@conversation.id} conta=#{@account.id} card=#{card.id} dono=#{dono.id} " \
      "atendente=#{@conversation.assignee_id || '-'}"
    )
  end
end
