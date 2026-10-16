require 'rails_helper'

RSpec.describe 'Autonomia store checkout and activation', type: :request do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:account) { create(:account) }
  let(:user) { create(:super_admin) }
  let(:namespace) { fixture.dig('checkoutResponse', 'namespace') }
  let(:buyer_subject) { fixture.dig('checkoutResponse', 'buyer', 'cognitoSub') }
  let(:client) { instance_double(Autonomia::Financial::StoreCheckoutClient) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/financial/store" }
  let(:client_intent) { SecureRandom.uuid }
  let(:request_body) { fixture.fetch('checkoutRequest').merge('clientIntent' => client_intent) }

  before do
    create(:account_user, account: account, user: user, role: :administrator)
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return('fictitious-access')
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return(buyer_subject)
    configuration = instance_double(Autonomia::Financial::StoreConfiguration, namespace: namespace)
    allow(Autonomia::Financial::StoreConfiguration).to receive(:new).and_return(configuration)
    allow(Autonomia::Financial::StoreCheckoutClient).to receive(:new).and_return(client)
    allow(client).to receive(:catalog!).and_return(
      'data' => [{ 'target' => { 'type' => 'feature', 'featureKey' => 'prospecting' },
                   'offers' => [{ 'price' => { 'id' => fixture.dig('checkoutRequest', 'servicePlanPriceId') } }] }],
      'pagination' => { 'totalPages' => 1 }
    )
  end

  it 'rejects ordinary account administrators before invoking Financial' do
    admin = create(:user, :administrator, account: account)
    post "#{base_path}/checkout", params: request_body, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Autonomia::Sso::TokenStore).not_to have_received(:authorization_token_for)
    expect(Autonomia::Financial::StoreCheckoutClient).not_to have_received(:new)
  end

  it 'persists the intent before invoking Financial and reuses it on duplicate requests' do
    ids = []
    allow(client).to receive(:checkout!) do |payload, idempotency_key:|
      intent = Autonomia::Store::CheckoutIntent.find(idempotency_key)
      expect(intent.payload).to eq(payload)
      expect(intent.buyer_subject).to eq(buyer_subject)
      ids << idempotency_key
      fixture.fetch('checkoutResponse').merge('checkoutIntentId' => idempotency_key)
    end
    2.times { post "#{base_path}/checkout", params: request_body, headers: auth_headers(user), as: :json }
    expect(response).to have_http_status(:created)
    expect(Autonomia::Store::CheckoutIntent.count).to eq(1)
    expect(ids.uniq.size).to eq(1)
    expect(Autonomia::Store::Activation.count).to eq(0)
    expect(Autonomia::Store::CheckoutIntent.last.attributes.values).not_to include(fixture['checkoutResponse']['checkoutUrl'])
  end

  it 'records an unknown outcome without inventing a second checkout' do
    allow(client).to receive(:checkout!).and_raise(Autonomia::Financial::StoreClientError.new('TRANSPORT_ERROR', status: 503, outcome: 'unknown'))
    post "#{base_path}/checkout", params: request_body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(Autonomia::Store::CheckoutIntent.last.state).to eq('reconciling')
    expect(Autonomia::Store::CheckoutIntent.last.client_intent).to eq(client_intent)
  end

  it 'persists explicit reconciliation before queueing without creating another checkout' do
    allow(client).to receive(:checkout!).and_raise(Autonomia::Financial::StoreClientError.new('TRANSPORT_ERROR', status: 503, outcome: 'unknown'))
    post "#{base_path}/checkout", params: request_body, headers: auth_headers(user), as: :json
    record = Autonomia::Store::CheckoutIntent.last
    expect { post "#{base_path}/checkout/#{record.id}/reconcile", headers: auth_headers(user), as: :json }
      .to have_enqueued_job(Autonomia::Store::CheckoutRecoveryJob).with(record.id)
    expect(response).to have_http_status(:accepted)
    expect(record.reload.reconciliation_requested).to be(true)
    expect(client).to have_received(:checkout!).once
  end

  %w[account buyer].product(%w[status resolve reconcile]).each do |mismatch, action|
    it "does not read or change a checkout through #{action} with a different #{mismatch}" do
      original_account = mismatch == 'account' ? create(:account) : account
      create(:account_user, user: user, account: original_account, role: :administrator) if mismatch == 'account'
      intent = Autonomia::Store::CheckoutIntent.create!(
        user: user, account: original_account, buyer_subject: mismatch == 'buyer' ? 'another-fictitious-subject' : buyer_subject,
        installation_id: namespace.fetch('installationId'), product_catalog_item_id: namespace.fetch('productCatalogItemId'),
        client_intent: client_intent, payload: fixture.fetch('checkoutRequest'), state: 'expired'
      )
      case action
      when 'status'
        get "#{base_path}/checkout/#{intent.id}", headers: auth_headers(user)
      when 'resolve'
        post "#{base_path}/checkout/resolve", params: { clientIntent: client_intent }, headers: auth_headers(user), as: :json
      when 'reconcile'
        post "#{base_path}/checkout/#{intent.id}/reconcile", headers: auth_headers(user), as: :json
      end
      expect(intent.reload).to have_attributes(state: 'expired', error_code: nil, reconciliation_requested: false)
      expect(response).to have_http_status(:not_found)
      expect(Autonomia::Financial::StoreCheckoutClient).not_to have_received(:new)
      expect(Autonomia::Store::CheckoutRecoveryJob).not_to have_been_enqueued
    end
  end

  %w[canceled unpaid active].each do |subscription_status|
    it "checks the #{subscription_status} root before allowing another purchase after expiration" do
      checkout = fixture.fetch('checkoutStatusResponse').fetch('checkout').deep_dup
      intent = Autonomia::Store::CheckoutIntent.create!(
        user: user, account: account, buyer_subject: buyer_subject, installation_id: namespace.fetch('installationId'),
        product_catalog_item_id: namespace.fetch('productCatalogItemId'), client_intent: client_intent,
        payload: fixture.fetch('checkoutRequest'), checkout_session_id: checkout.fetch('id'),
        service_subscription_id: checkout.fetch('serviceSubscriptionId'), state: 'expired'
      )
      checkout['checkoutIntentId'] = intent.id
      checkout['status'] = 'expired'
      allow(client).to receive(:checkout_state!).and_return('checkout' => checkout)
      allow(client).to receive(:checkout!)
      entry = fixture.fetch('serviceSubscriptionDetailResponse').deep_dup
      entry['data']['subscription']['status'] = subscription_status
      allow(client).to receive(:service_subscription!).and_return(entry)
      get "#{base_path}/checkout/#{intent.id}", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('operation', 'canStartNewCheckout')).to eq(subscription_status == 'canceled')
      expect(intent.reload.state).to eq('expired')
      expect(client).not_to have_received(:checkout!)
    end
  end

  it 'rejects browser-provided buyer, quota and account overrides at the checkout boundary' do
    post "#{base_path}/checkout", params: request_body.merge('buyer' => { 'cognitoSub' => 'other' }, 'quantity' => 99),
                                  headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Store::CheckoutIntent.count).to eq(0)
    expect(Autonomia::Financial::StoreCheckoutClient).not_to have_received(:new)
  end

  it 'rejects a beneficiary account where the buyer is not an administrator' do
    other = create(:account)
    post "#{base_path}/activations", headers: auth_headers(user), as: :json,
                                     params: { serviceSubscriptionId: fixture.dig('reservationResponse', 'reservation', 'serviceSubscriptionId'),
                                               accountId: other.id, clientIntent: client_intent }
    expect(response).to have_http_status(:not_found)
    expect(Autonomia::Financial::StoreCheckoutClient).not_to have_received(:new)
  end

  it 'queues activation without granting the feature or overriding its configured limit' do
    entry = fixture.fetch('serviceSubscriptionDetailResponse')
    allow(client).to receive(:service_subscription!).and_return(entry)
    payload = { serviceSubscriptionId: entry.dig('data', 'subscription', 'id'), accountId: account.id, clientIntent: client_intent }
    post "#{base_path}/activations", headers: auth_headers(user), as: :json, params: payload
    expect(response).to have_http_status(:accepted)
    activation = Autonomia::Store::Activation.last
    expect(activation.state).to eq('preparing')
    expect(activation.metric_key).to eq('feature_activations')
    expect(response.parsed_body.dig('data', 'available')).to be(false)
    expect(Autonomia::Store::Entitlement.count).to eq(0)
  end

  it 'rejects activation when the Financial contract has not authorized access' do
    entry = fixture.fetch('serviceSubscriptionDetailResponse')
    entry['data']['subscription']['status'] = 'unpaid'
    entry['data']['subscription']['access']['allowed'] = false
    allow(client).to receive(:service_subscription!).and_return(entry)
    payload = { serviceSubscriptionId: entry.dig('data', 'subscription', 'id'), accountId: account.id, clientIntent: client_intent }
    post "#{base_path}/activations", headers: auth_headers(user), as: :json, params: payload
    expect(response).to have_http_status(:conflict)
    expect(Autonomia::Store::Activation.count).to eq(0)
  end

  it 'does not replace checkout identifiers already correlated by a callback when polling status' do
    checkout = fixture.fetch('checkoutStatusResponse').fetch('checkout').deep_dup
    intent = Autonomia::Store::CheckoutIntent.create!(
      user: user, account: account, buyer_subject: buyer_subject, installation_id: namespace.fetch('installationId'),
      product_catalog_item_id: namespace.fetch('productCatalogItemId'), client_intent: client_intent,
      payload: fixture.fetch('checkoutRequest'), checkout_session_id: checkout.fetch('id'),
      service_subscription_id: checkout.fetch('serviceSubscriptionId'), state: 'completed'
    )
    checkout['checkoutIntentId'] = intent.id
    checkout['status'] = 'completed'
    checkout['serviceSubscriptionId'] = SecureRandom.uuid
    allow(client).to receive(:checkout_state!).and_return('checkout' => checkout)
    get "#{base_path}/checkout/#{intent.id}", headers: auth_headers(user)
    expect(response).to have_http_status(:bad_gateway)
    expect(intent.reload.service_subscription_id).to eq(fixture.dig('checkoutStatusResponse', 'checkout', 'serviceSubscriptionId'))
    expect(intent.state).to eq('completed')
  end

  it 'does not guess a quota metric when the contract contains several allocation limits' do
    entry = fixture.fetch('serviceSubscriptionDetailResponse')
    entry['data']['subscription']['limits'] << entry['data']['subscription']['limits'].first.merge('metricKey' => 'other_limit')
    allow(client).to receive(:service_subscription!).and_return(entry)
    payload = { serviceSubscriptionId: entry.dig('data', 'subscription', 'id'), accountId: account.id, clientIntent: client_intent }
    post "#{base_path}/activations", headers: auth_headers(user), as: :json, params: payload
    expect(response).to have_http_status(:conflict)
    expect(Autonomia::Store::Activation.count).to eq(0)
  end

  it 'persists the canonical agent target and its configured capacity metric before enqueueing' do
    principal = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Example principal', agent_type: 'custom')
    target = { 'type' => 'agent', 'installationId' => namespace.fetch('installationId'), 'principalAgentId' => principal.id }
    entry = fixture.fetch('serviceSubscriptionDetailResponse')
    entry['data']['target'] = target
    entry['data']['subscription']['limits'].first['metricKey'] = 'accounts'
    allow(client).to receive(:service_subscription!).and_return(entry)
    post "#{base_path}/activations", headers: auth_headers(user), as: :json,
                                     params: { serviceSubscriptionId: entry.dig('data', 'subscription', 'id'),
                                               accountId: account.id, clientIntent: client_intent }
    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Store::Activation.last).to have_attributes(target: target, feature_key: nil, agent_id: nil, metric_key: 'accounts')
    expect(Autonomia::Agents::Agent.where(principal_agent: principal)).to be_empty
  end

  it 'requires a new explicit activation intent before replacing an expired reservation' do
    entry = fixture.fetch('serviceSubscriptionDetailResponse')
    allow(client).to receive(:service_subscription!).and_return(entry)
    payload = { serviceSubscriptionId: entry.dig('data', 'subscription', 'id'), accountId: account.id, clientIntent: client_intent }
    post "#{base_path}/activations", headers: auth_headers(user), as: :json, params: payload
    activation = Autonomia::Store::Activation.last
    old_reservation = SecureRandom.uuid
    activation.update!(state: 'failed', error_code: 'RESERVATION_EXPIRED', reservation_id: old_reservation, reserve_attempted: true)
    post "#{base_path}/activations", headers: auth_headers(user), as: :json, params: payload
    expect(activation.reload).to have_attributes(state: 'failed', reservation_id: old_reservation, operation_intent: client_intent)
    payload[:clientIntent] = SecureRandom.uuid
    post "#{base_path}/activations", headers: auth_headers(user), as: :json, params: payload
    expect(response).to have_http_status(:accepted)
    expect(activation.reload).to have_attributes(state: 'preparing', reservation_id: nil, reserve_attempted: false,
                                                 operation_intent: payload[:clientIntent], error_code: nil)
    expect(Autonomia::Store::Activation.count).to eq(1)
  end

  it 'rejects browser target injection, and resolves new checkout targets from the published price' do
    principal = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Example principal', agent_type: 'custom')
    target = { 'type' => 'agent', 'installationId' => namespace.fetch('installationId'), 'principalAgentId' => principal.id }
    allow(client).to receive(:catalog!).and_return('data' => [{ 'target' => target,
                                                                'offers' => [{ 'price' => { 'id' => request_body['servicePlanPriceId'] } }] }],
                                                   'pagination' => { 'totalPages' => 1 })
    post "#{base_path}/checkout", params: request_body.merge('target' => target), headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    allow(client).to receive(:checkout!) do |payload, idempotency_key:|
      expect(Autonomia::Store::CheckoutIntent.find(idempotency_key).target).to eq(target)
      expect(payload.keys).not_to include('target')
      fixture.fetch('checkoutResponse').merge('checkoutIntentId' => idempotency_key)
    end
    post "#{base_path}/checkout", params: request_body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:created)
  end
end
