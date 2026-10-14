# frozen_string_literal: true

class Autonomia::Store::EventJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 30.seconds, attempts: 5

  def perform(id)
    event = Autonomia::Store::Event.find_by(id: id)
    return unless event

    event.with_lock do
      return unless event.state == 'pending'

      if event.payload.fetch('type') == 'store.entitlements.snapshot'
        Autonomia::Store::Projection.apply!(event.payload)
      else
        apply_subscription!(event.payload)
      end
      event.update!(state: 'processed', processed_at: Time.current, error_code: nil)
    end
  end

  private

  def apply_subscription!(event)
    data = event.fetch('data')
    return unless data['checkoutIntentId']

    intent = Autonomia::Store::CheckoutIntent.find_by(id: data['checkoutIntentId'])
    return unless intent

    subscription = data.fetch('subscription')
    intent.with_lock do
      return unless subscription_matches?(intent, event) && linked_ids_match?(intent, data)

      version = Integer(event.fetch('accessVersion'), 10)
      return if version <= intent.access_version.to_i

      intent.update!(checkout_session_id: data['checkoutSessionId'], service_subscription_id: subscription['id'], access_version: version,
                     state: subscription.dig('access', 'allowed') ? 'completed' : intent.state, error_code: nil)
    end
  end

  def subscription_matches?(intent, event)
    data = event.fetch('data')
    expected = {
      'buyer' => { 'cognitoSub' => intent.buyer_subject }, 'planPriceId' => intent.payload.fetch('servicePlanPriceId'),
      'namespace' => { 'installationId' => intent.installation_id, 'productCatalogItemId' => intent.product_catalog_item_id }
    }
    event.fetch('namespace') == expected['namespace'] && data.fetch('buyer') == expected['buyer'] &&
      data.fetch('subscription').slice(*expected.keys) == expected
  end

  def linked_ids_match?(intent, data)
    return false unless data['checkoutSessionId']

    [[intent.checkout_session_id, data['checkoutSessionId']],
     [intent.service_subscription_id, data.dig('subscription', 'id')]].all? do |expected, actual|
      expected.nil? || expected == actual
    end
  end
end
