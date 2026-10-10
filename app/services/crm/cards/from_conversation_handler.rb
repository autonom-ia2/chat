class Crm::Cards::FromConversationHandler
  Result = Struct.new(:card, :created, keyword_init: true)

  # new_subject: a pessoa pediu um assunto novo nesta conversa (#1142). Sem ele, reaproveita o card que a conversa
  # já tem (assunto atual), como sempre.
  def initialize(account:, user:, conversation:, requested_params:, new_subject: false)
    @account = account
    @user = user
    @conversation = conversation
    @requested_params = requested_params
    @new_subject = new_subject
  end

  def perform
    created = false
    card = nil

    @conversation.with_lock do
      card = existing_card
      yield card if card.present?
      next if card.present?

      card = create_card
      yield card
      created = true
    end

    Result.new(card: card, created: created)
  end

  private

  def existing_card
    return if @new_subject

    ::Crm::Cards::ConversationCardFinder.new(account: @account).find(@conversation)
  end

  def create_card
    ::Crm::Cards::Creator.new(
      account: @account,
      user: @user,
      params: merged_params,
      conversation: @conversation
    ).perform
  end

  def merged_params
    @requested_params.except(*::Crm::Cards::CreateParamsResolver::LINK_ATTRIBUTES)
                     .merge(default_stage_params)
  end

  def default_stage_params
    ::Crm::Cards::ConversationDefaultsResolver.new(
      account: @account,
      requested: @requested_params,
      conversation: @conversation
    ).perform
  end
end
