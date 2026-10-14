# frozen_string_literal: true

class Autonomia::Store::Activation < ApplicationRecord
  self.table_name = 'autonomia_store_activations'
  belongs_to :user, optional: true
  belongs_to :account, optional: true
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', optional: true
  validates :buyer_subject, :installation_id, :product_catalog_item_id, :service_subscription_id, :service_catalog_item_id,
            :resource_id, :metric_key, :operation_intent, :occurred_at, presence: true
  before_validation :set_feature_target
  validate :valid_target
  validates :state, inclusion: { in: %w[preparing reserved committed ready disabling disabled failed] }

  def resource_ref
    { 'type' => 'chatwoot.account', 'id' => resource_id }
  end

  def intent_key(action)
    "store:#{id}:#{operation_intent}:#{action}"
  end

  def public_payload(snapshot: nil)
    { id: id, accountId: account_id, serviceSubscriptionId: service_subscription_id, featureKey: feature_key,
      target: target, agentId: agent_id, state: state, available: available?(snapshot), errorCode: error_code }
  end

  private

  def set_feature_target
    self.target = { 'type' => 'feature', 'featureKey' => feature_key } if target.empty? && feature_key.present?
  end

  def valid_target
    Autonomia::Financial::StoreContract.validate!('target', target)
  rescue Autonomia::Financial::StoreContractError
    errors.add(:target, :invalid)
  end

  def available?(snapshot)
    return false unless state == 'ready' && snapshot
    return false if target['type'] == 'agent' && (!agent || agent.deleted? || !agent.store_access_allowed?)

    Autonomia::Store::GrantPolicy.allowed?(snapshot, subscription_id: service_subscription_id, reservation_id: reservation_id)
  end
end
