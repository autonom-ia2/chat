# frozen_string_literal: true

class Autonomia::Store::CheckoutIntent < ApplicationRecord
  self.table_name = 'autonomia_store_checkout_intents'
  belongs_to :user, optional: true
  belongs_to :account, optional: true
  validates :buyer_subject, :installation_id, :product_catalog_item_id, :payload, :client_intent, presence: true
  validates :state, inclusion: { in: %w[pending created payment_pending confirmation_pending reconciling completed expired failed] }

  def public_payload(can_start_new_checkout: false)
    { id: id, state: state, clientIntent: client_intent, errorCode: error_code, canStartNewCheckout: can_start_new_checkout }
  end

  def accepts_checkout_state?(incoming)
    return true if state == incoming
    return false if state == 'completed'
    return true if reconciliation_requested

    %w[expired failed].exclude?(state)
  end
end
