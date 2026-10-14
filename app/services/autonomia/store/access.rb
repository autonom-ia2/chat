# frozen_string_literal: true

class Autonomia::Store::Access
  def self.allowed?(account, feature_key)
    grants_allowed?(account, feature_key: feature_key)
  end

  def self.agent_allowed?(agent)
    principal = agent.principal_agent
    return false unless principal && !principal.deleted? && principal.principal_agent_id.nil? && principal.account.active?
    return false if principal.config['system_key'].present?

    grants_allowed?(agent.account, agent_id: agent.id)
  end

  def self.grants_allowed?(account, **target)
    return false unless account&.id && account.active?

    installation = ENV.fetch('FINANCIAL_STORE_INSTALLATION_ID', nil)
    product = ENV.fetch('FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID', nil)
    return false if installation.blank? || product.blank?

    join = <<~SQL.squish
      INNER JOIN autonomia_store_activations a ON a.account_id = autonomia_store_entitlements.account_id
      AND a.installation_id = autonomia_store_entitlements.installation_id
      AND a.product_catalog_item_id = autonomia_store_entitlements.product_catalog_item_id
      AND a.service_catalog_item_id = autonomia_store_entitlements.service_catalog_item_id
    SQL
    Autonomia::Store::Entitlement.where(account: account, installation_id: installation, product_catalog_item_id: product)
                                 .joins(join).where(a: target.merge(state: 'ready'))
                                 .pluck('a.service_subscription_id', 'a.reservation_id', :payload).any? do |subscription, reservation, snapshot|
      Autonomia::Store::GrantPolicy.allowed?(snapshot, subscription_id: subscription, reservation_id: reservation)
    end
  end
  private_class_method :grants_allowed?
end
