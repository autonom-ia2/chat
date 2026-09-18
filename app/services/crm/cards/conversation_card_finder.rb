class Crm::Cards::ConversationCardFinder
  def initialize(account:)
    @account = account
  end

  def find(conversation)
    active_cards.where(conversation_id: conversation.id).first ||
      active_cards.joins(:card_conversations).where(crm_card_conversations: { conversation_id: conversation.id }).order(:id).first
  end

  private

  def active_cards
    @active_cards ||= @account.crm_cards
                              .includes(:contact, :owner, :inbox, :stage, :pipeline, :primary_conversation)
                              .where.not(status: ::Crm::Card.statuses[:archived])
  end
end
