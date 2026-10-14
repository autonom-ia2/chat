# frozen_string_literal: true

class Autonomia::Store::CheckoutRecovery
  def self.apply!(intent, checkout)
    intent.with_lock do
      pairs = [[intent.checkout_session_id, checkout.fetch('id')], [intent.service_subscription_id, checkout['serviceSubscriptionId']]]
      unless pairs.all? { |expected, actual| expected.nil? || expected == actual }
        raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
      end

      unless intent.accepts_checkout_state?(checkout['status'])
        raise Autonomia::Financial::StoreClientError.new('RESPONSE_STATE_MISMATCH',
                                                         outcome: 'unknown')
      end

      intent.update!(state: checkout.fetch('status'), checkout_session_id: checkout.fetch('id'),
                     service_subscription_id: checkout['serviceSubscriptionId'], error_code: nil)
    end
  end

  def initialize(intent)
    @intent = intent
  end

  def run!
    return if @intent.state == 'completed' || (%w[expired failed].include?(@intent.state) && !@intent.reconciliation_requested)

    client = checkout_client!
    price = @intent.payload.fetch('servicePlanPriceId')
    response = if @intent.checkout_session_id
                 client.checkout_state!(@intent.checkout_session_id, intent_id: @intent.id, price_id: price)
               else
                 client.resolve_checkout!(@intent.id, price_id: price)
               end
    self.class.apply!(@intent, response.fetch('checkout'))
    reconcile!(client, price) if @intent.reconciliation_requested && @intent.state != 'completed'
  end

  private

  def reconcile!(client, price)
    body = { 'contractVersion' => 1, 'idempotencyKey' => "store:checkout:#{@intent.id}:reconcile" }
    response = client.reconcile_checkout!(@intent.checkout_session_id, body)
    remote = response.fetch('operation')
    persist_reconciliation!(remote)
    return unless remote['state'] == 'completed'

    result = client.checkout_state!(@intent.checkout_session_id, intent_id: @intent.id, price_id: price)
    unless result.dig('checkout', 'status') == 'completed'
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_STATE_MISMATCH', outcome: 'unknown')
    end

    self.class.apply!(@intent, result.fetch('checkout'))
  end

  def persist_reconciliation!(remote)
    @intent.with_lock do
      if @intent.reconciliation_operation_id && @intent.reconciliation_operation_id != remote.fetch('id')
        raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
      end

      @intent.update!(reconciliation_operation_id: remote.fetch('id'), reconciliation_state: remote.fetch('state'))
      @intent.update!(reconciliation_requested: false) if remote['state'] == 'blocked'
      @intent.update!(state: 'reconciling') if @intent.state != 'completed' && remote['state'] == 'pending'
    end
  end

  def eligible_user!
    user = @intent.user
    raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403) unless user.is_a?(SuperAdmin)

    membership = user.account_users.find_by(account_id: @intent.account_id)
    raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403) unless membership&.administrator? && @intent.account&.active?

    user
  end

  def checkout_client!
    eligible_user!
    Autonomia::Store::BuyerClient.fetch!(
      @intent,
      client_class: @intent.reconciliation_requested ? Autonomia::Financial::StoreLifecycleClient : Autonomia::Financial::StoreCheckoutClient,
      checkout_context: { 'checkoutIntentId' => @intent.id, 'accountId' => @intent.account_id.to_s }, checkout_target: @intent.target
    )
  end
end
