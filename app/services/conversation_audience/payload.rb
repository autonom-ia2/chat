# What the screen reads about a search by conversation (#2277), every few seconds while it reads. Money goes in
# dollars (what the account's AI key is charged) and in reais at the rate of the plan; people who could not receive
# when found leave the list and are only named at the end (phone and reason written by ConversationAudience::Wave;
# the save checks them again). People whose conversation the person can no longer open stay out (#2303 access review).
#
# With `since` (the cursor of the previous answer), people and left_aside carry only who changed after it: a search
# of thousands of people is not sent whole every few seconds. The cursor steps back OVERLAP, so a person written by a
# wave that was still committing is sent again rather than missed; the screen merges by id.
class ConversationAudience::Payload
  OVERLAP = 30.seconds

  def initialize(search, since: nil)
    @search = search
    @since = since
    @cursor = (Time.current - OVERLAP).iso8601(6)
  end

  def to_h
    {
      id: @search.id, status: @search.status, error: @search.error, request: @search.request, period: @search.period,
      plan: plan, read: @search.conversations_read, total: @search.conversations_total, cost: money(@search.spent_usd),
      people: people, left_aside: left_aside, campaign_import_id: @search.campaign_import_id, cursor: @cursor,
      skipped: skipped, ahead_minutes: ahead_minutes, finishing: finishing?
    }
  end

  private

  def plan
    plan = @search.plan
    return if plan.blank?

    {
      understood: plan['understood'], name: plan['name'], question: plan['question'], minutes: plan['minutes'],
      conversations: @search.conversations_total, cost: money(@search.estimate_usd), ceiling: money(@search.ceiling_usd)
    }
  end

  def money(usd)
    return if usd.nil?

    { usd: usd.to_f.round(4), brl: ConversationAudience::Cost.brl(usd, @search.usd_brl) }
  end

  def people
    rows.reject(&:left_aside).map do |row|
      { id: row.id, name: row.name, contact: row.contact, confidence: row.group, reason: row.reason, conversation_id: row.conversation_id }
    end
  end

  def left_aside
    rows.select(&:left_aside).map { |row| [row.name, row.left_aside, row.id] }
  end

  # Conversations of the batches the AI could not read (ConversationAudience::Wave): left out of the search.
  def skipped
    @search.batches.skipped.sum('cardinality(conversation_ids)')
  end

  # In line behind another search of the account: about how long the one reading still takes. nil when nobody else
  # reads, and the search starts on the next job.
  def ahead_minutes
    return unless @search.status == ConversationAudienceSearch::QUEUED

    other = ConversationAudienceSearch.where(account_id: @search.account_id, status: ConversationAudienceSearch::READING)
                                      .where.not(id: @search.id).first
    return if other.nil?

    left = 1 - (other.conversations_read.to_f / [other.conversations_total.to_i, 1].max)
    [(other.plan.to_h['minutes'].to_f * left).ceil, 1].max
  end

  # "Parar" while a wave is in flight: the wave still writes who it found, so the screen keeps reading until it ends.
  def finishing?
    @search.status == ConversationAudienceSearch::STOPPED && Redis::LockManager.new.locked?(ConversationAudience::ReadJob.lock_key(@search.id))
  end

  Row = Struct.new(:id, :name, :contact, :group, :reason, :conversation_id, :left_aside)

  # The reason sums up the conversation: only people whose conversation the person can still open.
  def rows
    @rows ||= begin
      all = changed.joins(:contact).order(:id)
                   .pluck(:id, 'contacts.name', :contact_masked, :group, :reason, :conversation_id, :left_aside)
                   .map { |values| Row.new(*values) }
      visible = ConversationAudience::Conversations.visible_ids(@search.account, @search.user, all.map(&:conversation_id))
      all.select { |row| visible.include?(row.conversation_id) }
    end
  end

  def changed
    @since ? @search.people.where('conversation_audience_people.updated_at > ?', @since) : @search.people
  end
end
