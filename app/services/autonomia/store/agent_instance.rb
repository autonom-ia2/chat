# frozen_string_literal: true

class Autonomia::Store::AgentInstance
  def self.principal!(target)
    principal = Autonomia::Agents::Agent.kept.find_by(id: target.fetch('principalAgentId'), principal_agent_id: nil)
    unless principal&.account&.active? && principal.config['system_key'].blank?
      raise Autonomia::Financial::StoreClientError.new('AGENT_PRINCIPAL_UNAVAILABLE', status: 409)
    end

    principal
  end

  def self.provision!(activation)
    principal = principal!(activation.target)
    instance = Autonomia::Agents::Agent.create_or_find_by!(account_id: activation.account_id, principal_agent_id: principal.id,
                                                           store_service_catalog_item_id: activation.service_catalog_item_id) do |agent|
      agent.name = principal.name
      agent.company_name = activation.account.name
      agent.created_by = activation.user
      agent.agent_type = principal.agent_type
      agent.mode = :guided
      agent.status = :active
      agent.enabled = true
      agent.config = {}
    end
    # A deleted instance is never silently resurrected by a retry or another buyer.
    raise Autonomia::Financial::StoreClientError.new('AGENT_INSTANCE_DELETED', status: 409) if instance.deleted?

    activation.update!(agent: instance)
    instance
  end

  def self.sync_access!(instance)
    instance.agent_inboxes.kept.find_each { |link| link.sync_mirror!(operating: instance.operating?) }
  end

  def self.sync_account!(account_id)
    Autonomia::Agents::Agent.kept.where(account_id: account_id).where.not(principal_agent_id: nil).find_each do |instance|
      sync_access!(instance)
    end
  end
end
