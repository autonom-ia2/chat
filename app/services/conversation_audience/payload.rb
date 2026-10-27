# What the screen reads about a search by conversation (#2277), every few seconds while it reads. Money goes in
# dollars (what the account's AI key is charged) and in reais at the rate of the plan; people who could not receive
# when found leave the list and are only named at the end (phone and reason written by ConversationAudience::Wave;
# the save checks them again). People whose conversation the person can no longer open stay out (#2303 access review).
class ConversationAudience::Payload
  def initialize(search)
    @search = search
  end

  def to_h
    {
      id: @search.id, status: @search.status, error: @search.error, request: @search.request, period: @search.period,
      plan: plan, read: @search.conversations_read, total: @search.conversations_total, cost: money(@search.spent_usd),
      people: people, left_aside: left_aside, campaign_import_id: @search.campaign_import_id
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
      { id: row.id, name: row.name, phone: row.phone, confidence: row.group, reason: row.reason, conversation_id: row.conversation_id }
    end
  end

  def left_aside
    rows.select(&:left_aside).map { |row| [row.name, row.left_aside] }
  end

  Row = Struct.new(:id, :name, :phone, :group, :reason, :conversation_id, :left_aside)

  # The reason sums up the conversation: only people whose conversation the person can still open.
  def rows
    @rows ||= begin
      all = @search.people.joins(:contact).order(:id)
                   .pluck(:id, 'contacts.name', :phone_masked, :group, :reason, :conversation_id, :left_aside)
                   .map { |values| Row.new(*values) }
      visible = ConversationAudience::Conversations.visible_ids(@search.account, @search.user, all.map(&:conversation_id))
      all.select { |row| visible.include?(row.conversation_id) }
    end
  end
end
