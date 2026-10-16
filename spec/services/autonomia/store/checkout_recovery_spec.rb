require 'rails_helper'

RSpec.describe Autonomia::Store::CheckoutRecovery do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:namespace) { fixture.fetch('checkoutResponse').fetch('namespace') }
  let(:user) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:client) { instance_double(Autonomia::Financial::StoreCheckoutClient) }
  let(:intent) do
    Autonomia::Store::CheckoutIntent.create!(user: user, account: account, buyer_subject: fixture.dig('checkoutResponse', 'buyer', 'cognitoSub'),
                                             installation_id: namespace.fetch('installationId'),
                                             product_catalog_item_id: namespace.fetch('productCatalogItemId'),
                                             client_intent: SecureRandom.uuid, payload: fixture.fetch('checkoutRequest'), state: 'reconciling',
                                             target: { 'type' => 'feature', 'featureKey' => 'prospecting' })
  end
  let(:checkout) do
    { 'id' => SecureRandom.uuid, 'status' => 'completed', 'serviceSubscriptionId' => SecureRandom.uuid }
  end

  before do
    create(:account_user, user: user, account: account, role: :administrator)
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).with(user).and_return('fictitious-access')
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return(intent.buyer_subject)
    allow(Autonomia::Financial::StoreConfiguration).to receive(:new).and_return(instance_double(Autonomia::Financial::StoreConfiguration,
                                                                                                namespace: namespace))
    allow(Autonomia::Financial::StoreCheckoutClient).to receive(:new).and_return(client)
    allow(client).to receive(:checkout!)
    allow(client).to receive(:resolve_checkout!).and_return('checkout' => checkout)
    allow(client).to receive(:checkout_state!).and_return('checkout' => checkout)
  end

  it 'recovers a lost confirmation by the same persisted intent, never checkout creation' do
    described_class.new(intent).run!
    expect(client).to have_received(:resolve_checkout!).with(intent.id, price_id: intent.payload.fetch('servicePlanPriceId'))
    expect(client).not_to have_received(:checkout!)
    expect(intent.reload).to have_attributes(state: 'completed', checkout_session_id: checkout['id'],
                                             service_subscription_id: checkout['serviceSubscriptionId'])
    expect(Autonomia::Store::Activation.count).to eq(0)
  end

  it 'uses the known checkout session when its identifier was saved' do
    intent.update!(checkout_session_id: checkout['id'])
    described_class.new(intent).run!
    expect(client).to have_received(:checkout_state!).with(checkout['id'], intent_id: intent.id, price_id: intent.payload.fetch('servicePlanPriceId'))
    expect(client).not_to have_received(:resolve_checkout!)
  end

  it 'leaves an indeterminate result pending and preserves the original intent' do
    allow(client).to receive(:resolve_checkout!).and_raise(Autonomia::Financial::StoreClientError.new('TIMEOUT', outcome: 'unknown'))
    Autonomia::Store::CheckoutRecoveryJob.perform_now(intent.id)
    expect(intent.reload).to have_attributes(state: 'reconciling', error_code: 'TIMEOUT', checkout_session_id: nil)
    expect(client).not_to have_received(:checkout!)
  end

  it 'does not start a new checkout when resolve reports not found' do
    allow(client).to receive(:resolve_checkout!).and_raise(Autonomia::Financial::StoreClientError.new('NOT_FOUND', status: 404))
    Autonomia::Store::CheckoutRecoveryJob.perform_now(intent.id)
    expect(intent.reload).to have_attributes(state: 'reconciling', error_code: 'NOT_FOUND')
    expect(client).not_to have_received(:checkout!)
  end

  it 'requires the original buyer, namespace and current account administrator authority' do
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return('other-fictitious-buyer')
    expect { described_class.new(intent).run! }.to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.code).to eq('FORBIDDEN') }
    expect(client).not_to have_received(:resolve_checkout!)
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return(intent.buyer_subject)
    user.account_users.find_by!(account: account).update!(role: :agent)
    expect { described_class.new(intent).run! }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'pauses rather than broadening authority when the OAuth session cannot refresh' do
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return(nil)
    Autonomia::Store::CheckoutRecoveryJob.perform_now(intent.id)
    expect(intent.reload).to have_attributes(state: 'reconciling', error_code: 'UNAUTHORIZED')
    expect(client).not_to have_received(:resolve_checkout!)
  end

  it 'does not regress a confirmation that arrived during recovery' do
    intent.update!(state: 'completed', checkout_session_id: checkout['id'], service_subscription_id: checkout['serviceSubscriptionId'])
    expect { described_class.apply!(intent, checkout.merge('status' => 'payment_pending')) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.code).to eq('RESPONSE_STATE_MISMATCH') }
    expect(intent.reload.state).to eq('completed')
    expect(client).not_to have_received(:resolve_checkout!)
  end

  it 'rejects replacing known identifiers' do
    intent.update!(checkout_session_id: SecureRandom.uuid)
    expect { described_class.new(intent).run! }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
      expect(e.code).to eq('RESPONSE_TARGET_MISMATCH')
    }
  end

  it 'never polls terminal intents' do
    %w[completed expired failed].each do |state|
      intent.update!(state: state)
      described_class.new(intent).run!
    end
    expect(client).not_to have_received(:resolve_checkout!)
    expect(client).not_to have_received(:checkout_state!)
  end

  it 'cannot revive an expired checkout with a delayed pending response' do
    intent.update!(state: 'expired', checkout_session_id: checkout['id'])
    expect { described_class.apply!(intent, checkout.merge('status' => 'created')) }
      .to raise_error(Autonomia::Financial::StoreClientError) { |e| expect(e.code).to eq('RESPONSE_STATE_MISMATCH') }
    expect(intent.reload.state).to eq('expired')
  end

  context 'when payment verification is explicitly requested' do
    let(:client) { instance_double(Autonomia::Financial::StoreLifecycleClient) }
    let(:remote) { { 'operation' => { 'id' => SecureRandom.uuid, 'state' => 'completed' } } }

    before do
      intent.update!(reconciliation_requested: true)
      allow(Autonomia::Financial::StoreLifecycleClient).to receive(:new).and_return(client)
      allow(client).to receive(:reconcile_checkout!).and_return(remote)
      pending = checkout.merge('status' => 'reconciling')
      allow(client).to receive(:resolve_checkout!).and_return('checkout' => pending)
      allow(client).to receive(:checkout_state!).and_return('checkout' => checkout)
    end

    it 'resolves the original session before reconciling and confirms only from canonical checkout state' do
      described_class.new(intent).run!
      expect(client).to have_received(:reconcile_checkout!).with(checkout['id'], 'contractVersion' => 1,
                                                                                 'idempotencyKey' => "store:checkout:#{intent.id}:reconcile")
      expect(intent.reload.state).to eq('completed')
      expect(client).not_to have_received(:checkout!)
      expect(Autonomia::Store::Activation.count).to eq(0)
    end

    it 'leaves a pending reconciliation blocked and keeps its original key across recovery' do
      remote['operation']['state'] = 'pending'
      allow(client).to receive(:checkout_state!).and_return('checkout' => checkout.merge('status' => 'reconciling'))
      2.times { described_class.new(intent).run! }
      expect(intent.reload).to have_attributes(state: 'reconciling', reconciliation_state: 'pending')
      expect(client).to have_received(:reconcile_checkout!).with(checkout['id'], 'contractVersion' => 1,
                                                                                 'idempotencyKey' => "store:checkout:#{intent.id}:reconcile").twice
      expect(client).not_to have_received(:checkout!)
    end

    it 'does not consider a gateway operation receipt permission when canonical checkout is unconfirmed' do
      allow(client).to receive(:checkout_state!).and_return('checkout' => checkout.merge('status' => 'reconciling'))
      expect { described_class.new(intent).run! }.to raise_error(Autonomia::Financial::StoreClientError)
      expect(intent.reload.state).to eq('reconciling')
      expect(Autonomia::Store::Activation.count).to eq(0)
    end

    it 'stops automatic retries after Financial blocks the reconciliation' do
      remote['operation']['state'] = 'blocked'
      described_class.new(intent).run!
      expect(intent.reload).to have_attributes(reconciliation_requested: false, reconciliation_state: 'blocked')
    end

    it 'does not replace a known remote operation during replay' do
      intent.update!(reconciliation_operation_id: SecureRandom.uuid)
      expect { described_class.new(intent).run! }.to raise_error(Autonomia::Financial::StoreClientError) { |e|
        expect(e.code).to eq('RESPONSE_TARGET_MISMATCH')
      }
    end
  end
end
