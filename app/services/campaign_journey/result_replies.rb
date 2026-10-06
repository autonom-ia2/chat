# "Responderam" of a campaign result (#1007, PRD §6.5 and §6.10): the contacts whose conversation got
# the campaign mark of #1002 (a message received within 72h of the send, CampaignJourney::ReplyMarker).
# Read from the conversations' mark mirror `campaign_source_ids`, the same text probe the Kanban
# campaign filter uses (Crm::Cards::SharedFilters#apply_campaign_filter), so the trigram index on the
# mirror serves both. A contact counts once per campaign, whatever the number of conversations.
#
# "Viraram negócio no CRM" (Gestão): CRM cards linked to a conversation marked by the campaign, as the
# primary conversation or through crm_card_conversations — the cards the Kanban shows when filtered by
# that campaign. `won` is the part of them already won.
class CampaignJourney::ResultReplies
  CAMPAIGN_MARK_PROBE = '%"campaign:%'.freeze
  MARK_JOIN = "CROSS JOIN LATERAL jsonb_array_elements_text(conversations.additional_attributes -> 'campaign_source_ids') " \
              'AS campaign_mark(source_id)'.freeze

  def initialize(account, source_ids)
    @account = account
    @source_ids = Array(source_ids).compact.uniq
  end

  # { source_id => contacts that replied }
  def counts
    return {} if @source_ids.empty?

    marked.group('campaign_mark.source_id').distinct.count(:contact_id)
  end

  def contact_ids
    return [] if @source_ids.empty?

    marked.distinct.pluck(:contact_id)
  end

  # { contact_id => display_id } of the latest marked conversation the user can open.
  def conversations_by_contact(contact_ids, visible_conversations)
    return {} if @source_ids.empty? || contact_ids.blank?

    marked.where(contact_id: contact_ids, id: visible_conversations.select(:id))
          .order(:created_at).pluck(:contact_id, :display_id).to_h
  end

  # Latest marked conversation per contact (id, display_id, contact_id), newest first.
  def latest_conversations
    return Conversation.none if @source_ids.empty?

    ids = marked.group(:contact_id).maximum(:id).values
    @account.conversations.where(id: ids).order(id: :desc)
  end

  def deals
    return { cards: 0, won: 0 } if @source_ids.empty?

    conversation_ids = marked.select(:id)
    linked = Crm::CardConversation.where(account_id: @account.id, conversation_id: conversation_ids).select(:card_id)
    account_cards = Crm::Card.where(account_id: @account.id)
    cards = account_cards.where(conversation_id: conversation_ids).or(account_cards.where(id: linked))
    { cards: cards.count, won: cards.won.count }
  end

  private

  def marked
    @account.conversations
            .where("conversations.additional_attributes ->> 'campaign_source_ids' ILIKE ?", CAMPAIGN_MARK_PROBE)
            .joins(MARK_JOIN)
            .where(campaign_mark: { source_id: @source_ids })
  end
end
