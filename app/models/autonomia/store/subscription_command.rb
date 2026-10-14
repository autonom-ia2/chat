# frozen_string_literal: true

class Autonomia::Store::SubscriptionCommand < ApplicationRecord
  self.table_name = 'autonomia_store_subscription_commands'
  belongs_to :user, optional: true
  validates :buyer_subject, :installation_id, :product_catalog_item_id, :service_subscription_id, :client_intent, presence: true
  validates :command_action, inclusion: { in: %w[schedule resume] }
  validates :state, inclusion: { in: %w[pending confirmed blocked] }
  validates :expected_version, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 9_007_199_254_740_991 }

  def financial_payload
    { 'contractVersion' => 1, 'expectedVersion' => expected_version, 'idempotencyKey' => id }
  end

  def public_payload
    { id: id, serviceSubscriptionId: service_subscription_id, action: command_action, state: state, errorCode: error_code }
  end
end
