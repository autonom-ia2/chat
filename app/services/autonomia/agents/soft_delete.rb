class Autonomia::Agents::SoftDelete
  def initialize(agent:, actor:, request_id: nil, reason: 'user_request')
    @agent = agent
    @actor = actor
    @request_id = request_id
    @reason = reason
  end

  def perform
    @agent.with_lock do
      next false if @agent.deleted?

      deleted_at = Time.current
      archive_inbox_links!(deleted_at)
      archive_agent!(deleted_at)
      metadata = audit_metadata(deleted_at)
      Audited.audit_class.create!(auditable: @agent, associated: @agent.account, user: @actor,
                                 action: 'destroy', comment: 'Logical deletion',
                                 request_uuid: @request_id, audited_changes: metadata)
      ActiveRecord.after_all_transactions_commit { Rails.logger.info(metadata.to_json) }
      true
    end
  end

  private

  def archive_inbox_links!(deleted_at)
    @agent.agent_inboxes.kept.find_each do |link|
      link.sync_mirror!(operating: false)
      # Only the live routing join is removed. Keep the bot (historical message sender)
      # and the archived AgentInbox (agent, inbox and bot IDs) for recovery.
      AgentBotInbox.where(inbox_id: link.inbox_id, agent_bot_id: link.agent_bot_id).destroy_all
      link.update_columns(deleted_at: deleted_at, updated_at: deleted_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def archive_agent!(deleted_at)
    # Historical validation errors must not prevent deletion; mirror synchronization is explicit above.
    # rubocop:disable Rails/SkipsModelValidations
    @agent.update_columns(deleted_at: deleted_at, deleted_by_id: @actor&.id,
                          enabled: false, status: Autonomia::Agents::Agent.statuses[:paused], updated_at: deleted_at)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def audit_metadata(deleted_at)
    { event: 'autonomia.agent.soft_deleted', account_id: @agent.account_id,
      agent_id: @agent.id, actor_id: @actor&.id, reason: @reason,
      deleted_at: deleted_at.iso8601(6), request_id: @request_id }
  end
end
