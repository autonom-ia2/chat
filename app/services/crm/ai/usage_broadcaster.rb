class Crm::Ai::UsageBroadcaster
  EVENT = 'crm.ai_usage.created'.freeze

  def self.broadcast(event)
    new(event).broadcast
  end

  def initialize(event)
    @event = event
  end

  # The cost in money goes only to who sees the account's costs: administrator or financial_view (#1969).
  def broadcast
    permitted_account_users.each do |account_user|
      token = account_user.user.pubsub_token
      next if token.blank?

      ActionCable.server.broadcast(token, { event: EVENT, data: payload(com_valores: account_user.permission_granted?('financial_view')) })
    end
  rescue StandardError => e
    Rails.logger.warn("[crm][ai][usage] broadcast failed event_id=#{event.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  attr_reader :event

  def permitted_account_users
    account_users.select { |account_user| report_policy(account_user).view? }
  end

  def account_users
    # `custom_role` is an Enterprise-only association (absent in FOSS). Eager-loading
    # it raises AssociationNotFound under FOSS, which the broadcast rescue would
    # silently swallow (zero recipients). Only eager-load it when it exists; the EE
    # ReportPolicy still reads it (lazily) where present.
    relation = AccountUser.human.where(account_id: event.account_id).includes(:user)
    relation = relation.includes(:custom_role) if AccountUser.reflect_on_association(:custom_role)
    relation
  end

  def report_policy(account_user)
    Crm::ReportPolicy.new(
      { user: account_user.user, account: event.account, account_user: account_user },
      %i[crm report]
    )
  end

  def payload(com_valores:)
    data = {
      id: event.id,
      account_id: event.account_id,
      resource: Crm::Reports::AiUsage.resource_for_feature(event.feature),
      created_at: event.created_at.iso8601
    }.merge(token_payload)
    com_valores ? data.merge(cost_usd: event.cost_estimate.to_d.round(6).to_f) : data
  end

  def token_payload
    input = event.input_tokens.to_i
    output = event.output_tokens.to_i
    { input_tokens: input, cached_tokens: event.cached_tokens, output_tokens: output, total_tokens: input + output }
  end
end
