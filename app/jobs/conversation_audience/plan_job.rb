# Step 1 of a search by conversation (#2277): the planner turns the request into the rule, then the period is split
# in reader batches so the plan shows the real count, time and cost. The person waits on the screen ("Entendendo seu
# pedido…"), so it runs on the default queue, not behind the long readings.
class ConversationAudience::PlanJob < ApplicationJob
  queue_as :default

  def perform(search_id)
    search = ConversationAudienceSearch.find_by(id: search_id)
    return unless search&.status == ConversationAudienceSearch::PLANNING
    return fail!(search, ConversationAudience::Access::ERROR) unless ConversationAudience::Access.allowed?(search)

    credential = ConversationAudience::Credential.for(search.account)
    return fail!(search, 'no_key') if credential.nil?

    plan, cost = ConversationAudience::Planner.new(search, credential: credential).call
    plan['question'] ? ask(search, plan, cost) : planned(search, plan, cost)
  # Any failure ends the planning, so the person is never left with a search stuck in "planning" (one search at a
  # time per person). The AI's error is logged by status only: the message may echo the request.
  rescue StandardError => e
    Rails.logger.warn("[conversation_audience][plan] search=#{search_id} #{e.class}: #{e.try(:status)}")
    fail!(search, 'plan_error')
  end

  private

  def ask(search, plan, cost)
    search.update!(plan: plan, status: ConversationAudienceSearch::QUESTION, spent_usd: search.spent_usd + cost)
  end

  def planned(search, plan, cost)
    sizes = ConversationAudience::Batches.build!(search)
    estimate = ConversationAudience::Cost.estimate_usd(sizes[:chars], sizes[:batches])
    spent = search.spent_usd + cost
    search.update!(
      plan: plan.merge('minutes' => ConversationAudience::Cost.minutes(sizes[:batches])), status: ConversationAudienceSearch::PLANNED,
      spent_usd: spent, conversations_total: sizes[:conversations], conversations_read: 0, estimate_usd: estimate,
      ceiling_usd: spent + (estimate * ConversationAudience::Cost::CEILING_FACTOR), usd_brl: ConversationAudience::Cost.usd_brl_rate
    )
  end

  def fail!(search, error)
    search&.update!(status: ConversationAudienceSearch::FAILED, error: error)
  end
end
