# Multifunil 5b (#1145): a pessoa responde à sugestão da IA no painel Assuntos (modo Sugerir).
#
# Aceitar faz o que a IA faria no modo Automática, mas como o "Novo assunto" feito à mão: a pessoa é a autora (e dona
# do card criado quando a conversa não tem responsável). Cria o card do pedido novo na primeira etapa do funil (e ele
# vira o assunto atual), dá o nome sugerido ao assunto atual, ou volta a um assunto aberto. Ignorar só marca a
# sugestão. Tudo no lock da conversa, e só vale para sugestão ainda esperando: outra pessoa pode ter respondido, ou uma
# mensagem nova ter trocado a sugestão. Sugestão que deixou de fazer sentido (card fechado ou apagado, funil arquivado
# ou fora da caixa, caixa que saiu do modo Sugerir — #1221) expira, para o aviso não ficar preso na tela.
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
    when 'rename', 'focus' then decision.card&.open? || false
    else false
    end
  end

  # A primeira etapa do funil sugerido, se ele segue ativo e ligado à caixa da conversa.
  def self.pipeline_stage(decision)
    pipeline = decision.pipeline
    return unless pipeline&.active? && pipeline.pipeline_inboxes.exists?(inbox_id: decision.conversation.inbox_id)

    pipeline.stages.order(:position, :id).first
  end

  def initialize(decision:, user:)
    @decision = decision
    @conversation = decision.conversation
    @account = decision.account
    @user = user
  end

  def accept
    card = nil
    evento = nil
    travado do
      expirar_sem_sentido!
      card, evento = aplicar
      @decision.update!(state: 'accepted', card: card)
    end
    Crm::Cards::Broadcaster.broadcast(card, evento)
    Crm::Subjects::Notifier.notify(@conversation)
    card
  end

  def dismiss
    travado { @decision.update!(state: 'dismissed') }
    Crm::Subjects::Notifier.notify(@conversation)
    @decision
  end

  private

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
                metadata: { 'subject' => { 'source' => 'ai', 'named_at' => Time.current.iso8601 } } }
    ).perform
  end

  def dar_nome(card)
    card.update!(title: @decision.title, metadata: Crm::Subjects::Naming.metadata(card, 'ai'))
    Crm::ActivityLogger.new(card: card, actor: @user, event_type: 'update', payload: { title: @decision.title },
                            conversation: @conversation).perform
    card
  end

  def focar(card)
    Crm::Cards::Focus.new(account: @account, card: card, conversation: @conversation).perform
    card
  end
end
