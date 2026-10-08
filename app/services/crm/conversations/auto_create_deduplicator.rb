class Crm::Conversations::AutoCreateDeduplicator
  DEDUP_WINDOW_ENV = 'CRM_AUTO_CREATE_DEDUP_WINDOW_DAYS'.freeze
  DEFAULT_DEDUP_WINDOW_DAYS = 30

  Result = Struct.new(:card, :reason, :window_days, keyword_init: true)

  def initialize(account:, conversation:, pipeline_inbox:)
    @account = account
    @conversation = conversation
    @pipeline_inbox = pipeline_inbox
  end

  def perform(active_cards)
    conversation_match = conversation_card(active_cards)
    return Result.new(card: conversation_match, window_days: window_days) if conversation_match.present?

    contact_match = contact_pipeline_card(active_cards)
    Result.new(
      card: contact_match,
      reason: contact_match.present? ? 'contact_inbox_pipeline' : nil,
      window_days: window_days
    )
  end

  private

  # Conversa já com card aberto: reaproveita o assunto atual dela, na mesma ordem do ConversationCardFinder.
  def conversation_card(active_cards)
    Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).merge(active_cards).first
  end

  def contact_pipeline_card(active_cards)
    return if @conversation.contact_id.blank?
    return if dedup_window_started_at.blank?

    active_cards
      .where(
        contact_id: @conversation.contact_id,
        inbox_id: @conversation.inbox_id,
        pipeline_id: @pipeline_inbox.pipeline_id
      )
      .where('COALESCE(crm_cards.last_activity_at, crm_cards.updated_at) >= ?', dedup_window_started_at)
      .order(last_activity_at: :desc, id: :desc)
      .first
  end

  def dedup_window_started_at
    return if window_days <= 0

    window_days.days.ago
  end

  def window_days
    @window_days ||= begin
      days = Integer(ENV.fetch(DEDUP_WINDOW_ENV, DEFAULT_DEDUP_WINDOW_DAYS), exception: false)
      days.presence || DEFAULT_DEDUP_WINDOW_DAYS
    end
  end
end
