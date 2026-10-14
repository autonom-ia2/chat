# frozen_string_literal: true

class Api::V1::Accounts::Autonomia::StoreCheckoutController < Api::V1::Accounts::Autonomia::StoreCustomerController
  def checkout
    @checkout_intent = build_intent!
    result = checkout_client.checkout!(@checkout_intent.payload, idempotency_key: @checkout_intent.id)
    @checkout_intent.with_lock do
      verify_checkout_links!(@checkout_intent, result.fetch('checkoutSessionId'), result['serviceSubscriptionId'])
      @checkout_intent.update!(checkout_session_id: result.fetch('checkoutSessionId'), service_subscription_id: result['serviceSubscriptionId'],
                               state: @checkout_intent.state == 'completed' ? 'completed' : 'created', error_code: nil)
    end
    render json: { operation: @checkout_intent.public_payload, checkoutUrl: result.fetch('checkoutUrl') }, status: :created
  end

  def checkout_status
    ::Autonomia::Financial::StoreContract.validate!('uuid', params[:id])
    @checkout_intent = checkout_scope.find(params[:id])
    intent = @checkout_intent
    result = if intent.checkout_session_id
               checkout_client.checkout_state!(intent.checkout_session_id, intent_id: intent.id, price_id: intent.payload.fetch('servicePlanPriceId'))
             else
               checkout_client.resolve_checkout!(intent.id, price_id: intent.payload.fetch('servicePlanPriceId'))
             end
    update_checkout_state!(result.fetch('checkout'))
  end

  def resolve_checkout
    body = customer_body('clientIntent')
    ::Autonomia::Financial::StoreContract.validate!('uuid', body['clientIntent'])
    @checkout_intent = checkout_scope.find_by!(client_intent: body.fetch('clientIntent'))
    result = checkout_client.resolve_checkout!(@checkout_intent.id, price_id: @checkout_intent.payload.fetch('servicePlanPriceId'))
    update_checkout_state!(result.fetch('checkout'))
  end

  def reconcile_checkout
    customer_body
    ::Autonomia::Financial::StoreContract.validate!('uuid', params[:id])
    @checkout_intent = checkout_scope.find(params[:id])
    verify_intent!(@checkout_intent, @checkout_intent.payload)
    @checkout_intent.with_lock do
      @checkout_intent.update!(reconciliation_requested: true, next_recovery_at: Time.current) unless @checkout_intent.state == 'completed'
    end
    ::Autonomia::Store::CheckoutRecoveryJob.perform_later(@checkout_intent.id) unless @checkout_intent.state == 'completed'
    render json: { operation: @checkout_intent.public_payload }, status: :accepted
  end

  private

  def build_intent!
    body = customer_body('clientIntent', 'servicePlanPriceId', 'limits')
    key = body.delete('clientIntent')
    ::Autonomia::Financial::StoreContract.validate!('uuid', key)
    ::Autonomia::Financial::StoreCheckoutContract.validate!('checkoutRequest', body)
    intent = checkout_scope.find_by(client_intent: key) || persist_intent!(key, body)
    verify_intent!(intent, body)
    intent
  end

  def persist_intent!(key, body)
    target = published_target!(body.fetch('servicePlanPriceId'))
    ::Autonomia::Store::CheckoutIntent.create_or_find_by!(user: Current.user, client_intent: key) do |record|
      record.account = Current.account
      record.installation_id = store_configuration.namespace.fetch('installationId')
      record.product_catalog_item_id = store_configuration.namespace.fetch('productCatalogItemId')
      record.buyer_subject = verified_subject
      record.payload = body
      record.target = target
    end
  end

  def published_target!(price_id)
    # Resolve the offer server-side. The signed target is never taken from browser input.
    result = store_client.catalog!(page: 1, page_size: 1, price_id: price_id)
    entry = result.fetch('data').find { |item| item.fetch('offers').any? { |offer| offer.dig('price', 'id') == price_id } }
    raise ::Autonomia::Financial::StoreClientError.new('OFFER_NOT_AVAILABLE', status: 409) unless entry

    target = entry.fetch('target')
    validate_activation_target!(target)
    target
  end

  def checkout_client
    intent = @checkout_intent
    verify_intent!(intent, intent.payload)
    ::Autonomia::Financial::StoreCheckoutClient.new(
      configuration: store_configuration, subject: verified_subject, authorization_token: @authorization_token,
      checkout_context: { 'checkoutIntentId' => intent.id, 'accountId' => intent.account_id.to_s }, checkout_target: intent.target
    )
  end

  def checkout_scope
    ::Autonomia::Store::CheckoutIntent.where(user: Current.user, account: Current.account, buyer_subject: verified_subject,
                                             installation_id: store_configuration.namespace.fetch('installationId'),
                                             product_catalog_item_id: store_configuration.namespace.fetch('productCatalogItemId'))
  end

  def verify_intent!(intent, body)
    valid = intent.payload == body && intent.account_id == Current.account.id && intent.buyer_subject == verified_subject &&
            intent.installation_id == store_configuration.namespace.fetch('installationId') &&
            intent.product_catalog_item_id == store_configuration.namespace.fetch('productCatalogItemId')
    raise ::Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409) unless valid
  end

  def update_checkout_state!(checkout)
    intent = @checkout_intent
    ::Autonomia::Store::CheckoutRecovery.apply!(intent, checkout)
    can_restart = if %w[expired failed].include?(intent.state) && intent.service_subscription_id
                    checkout_client.service_subscription!(intent.service_subscription_id).dig('data', 'subscription', 'status') == 'canceled'
                  else
                    false
                  end
    render json: { operation: intent.public_payload(can_start_new_checkout: can_restart), checkoutUrl: checkout['checkoutUrl'] }
  end

  def verify_checkout_links!(intent, session_id, subscription_id)
    matches = [[intent.checkout_session_id, session_id], [intent.service_subscription_id, subscription_id]].all? do |expected, actual|
      expected.nil? || expected == actual
    end
    raise ::Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown') unless matches
  end

  def render_store_error(error)
    @checkout_intent&.with_lock do
      @checkout_intent.update!(state: 'reconciling', error_code: error.code) unless @checkout_intent.state == 'completed'
    end
    render json: { error: 'Nao foi possivel concluir a operacao da loja.', code: error.code, outcome: error.outcome,
                   operation: @checkout_intent&.public_payload }, status: error.status
  end
end
