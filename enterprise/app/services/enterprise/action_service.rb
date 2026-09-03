module Enterprise::ActionService
  def add_sla(sla_policy_id)
    return if sla_policy_id.blank?
    # SLA is a premium feature; automation rules must not keep applying SLAs once it is disabled.
    return unless @account.feature_enabled?('sla')

    sla_policy = @account.sla_policies.find_by(id: sla_policy_id.first)
    return if sla_policy.nil?
    return if @conversation.sla_policy.present?
    # Upstream 4.17: never apply an SLA to a conversation whose contact is blocked.
    return unless @conversation.sla_applicable?
    # Fork: policies with exclude_groups skip WhatsApp group conversations.
    return if sla_policy.exclude_groups? && Crm::WhatsappGroupDetector.group_conversation?(@conversation)

    Rails.logger.info "SLA:: Adding SLA #{sla_policy.id} to conversation: #{@conversation.id}"
    @conversation.update!(sla_policy_id: sla_policy.id)
  end
end
