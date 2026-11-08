# Multifunil 5b (#1145): a pessoa responde à sugestão da IA no painel Assuntos (modo Sugerir).
#
# Aceitar faz o que a IA faria no modo Automática, mas como o "Novo assunto" feito à mão: a pessoa é a autora (e dona
# do card criado quando a conversa não tem responsável). Cria o card do pedido novo na primeira etapa do funil (e ele
# vira o assunto atual), dá o nome sugerido ao assunto atual, ou volta a um assunto aberto. Ignorar só marca a
# sugestão. Tudo no lock da conversa, e só vale para sugestão ainda esperando: outra pessoa pode ter respondido, ou uma
# mensagem nova ter trocado a sugestão. Sugestão que deixou de fazer sentido (card fechado ou apagado, funil arquivado
# ou fora da caixa, caixa que saiu do modo Sugerir — #1221) expira, para o aviso não ficar preso na tela.
#
# A sugestão que veio de uma dúvida da IA (#2162, Crm::Subjects::DuvidaSugerida) pode vir sem nome: aceita, o card
# nasce sem nome (o do contato, como o que a caixa cria) e a IA de assunto dá o nome quando o pedido ficar claro (#1918).
class Crm::Subjects::SuggestionResponder
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  SEM_SENTIDO = %w[closed_card pipeline_unavailable mode_changed].freeze

  def self.applicable?(decision)
    return false unless Crm::Subjects.sugerir?(decision.conversation)

    case decision.action
    when 'create' then pipeline_stage(decision).present?
    when 'focus' then card_aberto?(decision.card)
    # Uma pessoa deu nome ao card depois da sugestão: aceitar não troca o nome dela (#1260).
    when 'rename' then card_aberto?(decision.card) && !Crm::Subjects::Naming.named?(decision.card)
    else false
    end
  end

  def self.card_aberto?(card)
    card.present? && card.open?
  end

  # A primeira etapa do funil sugerido, se ele segue ativo, ligado à caixa da conversa e com a IA do funil ligada.
  def self.pipeline_stage(decision)
    pipeline = decision.pipeline
    return unless pipeline&.active? && Crm::Subjects.ia_do_funil?(pipeline)
    return unless pipeline.pipeline_inboxes.exists?(inbox_id: decision.conversation.inbox_id)

    pipeline.stages.order(:position, :id).first
  end

  def initialize(decision:, user:)
    @decision = decision
    @conversation = decision.conversation
    @account = decision.account
    @user = user
  end

  def accept
    ensure_funnel_allowed!
    card = nil
    evento = nil
    travado do
      expirar_sem_sentido!
      card, evento = aplicar
      @decision.update!(state: 'accepted', card: card)
    end
    Crm::Cards::Broadcaster.broadcast(card, evento)
    Crm::Subjects::Notifier.notify(@conversation)
    Crm::Ai::Observer.new(card: card).schedule_evaluation if @decision.action == 'create'
    card
  end

  def dismiss
    travado { @decision.update!(state: 'dismissed') }
    Crm::Subjects::Notifier.notify(@conversation)
    @decision
  end

  private

  # Acesso por funil (#1148, parte C): aceitar só cria card num funil que a pessoa tem, e só foca/renomeia card que ela vê.
  def ensure_funnel_allowed!
    allowed = if @decision.action == 'create'
                Crm::Access::CardGuard.new(user: @user, account: @account).create_allowed?(@decision.pipeline_id, conversation: @conversation)
              else
                @decision.card.nil? || Crm::Access::CardScope.new(user: @user, account: @account).allows?(@decision.card)
              end
    raise Pundit::NotAuthorizedError unless allowed
  end

  def travado(&)
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      raise Error, 'suggestion_expired' unless @decision.reload.state == 'suggested'

      yield
    end
  rescue Error => e
    expirar if SEM_SENTIDO.include?(e.code)
    raise
  end

  def expirar_sem_sentido!
    return if self.class.applicable?(@decision)
    raise Error, 'mode_changed' unless Crm::Subjects.sugerir?(@conversation)

    raise Error, @decision.action == 'create' ? 'pipeline_unavailable' : 'closed_card'
  end

  # Fora da transação do lock (que voltou atrás com o erro): a sugestão sem sentido sai da tela.
  def expirar
    @decision.update_columns(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def aplicar
    case @decision.action
    when 'create' then [criar, Events::Types::CRM_CARD_CREATED]
    when 'rename' then [dar_nome(@decision.card), Events::Types::CRM_CARD_UPDATED]
    when 'focus' then [focar(@decision.card), Events::Types::CRM_CARD_UPDATED]
    end
  end

  def criar
    Crm::Cards::Creator.new(
      account: @account, user: @user, conversation: @conversation,
      params: { pipeline_id: @decision.pipeline_id, stage_id: self.class.pipeline_stage(@decision).id, title: @decision.title,
                metadata: nome_da_ia }
    ).perform
  end

  # Sem nome (#2162), o card não leva a marca de nome dado: segue "sem assunto" até a IA dar o nome.
  def nome_da_ia
    return {} if @decision.title.blank?

    { 'subject' => { 'source' => 'ai', 'named_at' => Time.current.iso8601 } }
  end

  def dar_nome(card)
    card.update!(title: @decision.title, metadata: Crm::Subjects::Naming.metadata(card, 'ai'))
    Crm::ActivityLogger.new(card: card, actor: @user, event_type: 'update', payload: { title: @decision.title },
                            conversation: @conversation).perform
    card
  end

  def focar(card)
    Crm::Cards::Focus.new(account: @account, card: card, conversation: @conversation, user: @user).perform
    card
  end
end
