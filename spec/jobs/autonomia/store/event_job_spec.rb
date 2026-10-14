require 'rails_helper'

RSpec.describe Autonomia::Store::EventJob do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:payload) { fixture.fetch('subscriptionUpdatedEvent').deep_dup }
  let(:account) { create(:account) }
  let(:namespace) { payload.fetch('namespace') }
  let(:intent) do
    Autonomia::Store::CheckoutIntent.create!(
      id: payload.dig('data', 'checkoutIntentId'), user: create(:super_admin), account: account,
      buyer_subject: payload.dig('data', 'buyer', 'cognitoSub'), installation_id: namespace.fetch('installationId'),
      product_catalog_item_id: namespace.fetch('productCatalogItemId'), client_intent: SecureRandom.uuid,
      payload: fixture.fetch('checkoutRequest'), state: 'reconciling'
    )
  end

  def deliver!(data)
    event = Autonomia::Store::Event.create!(id: data.fetch('eventId'), body_sha256: Digest::SHA256.hexdigest(data.to_json), payload: data)
    described_class.perform_now(event.id)
    event.reload
  end

  it 'correlates an initial confirmation even when the checkout creation response was lost' do
    intent
    event = deliver!(payload)
    expect(intent.reload).to have_attributes(
      state: 'completed', checkout_session_id: payload.dig('data', 'checkoutSessionId'),
      service_subscription_id: payload.dig('data', 'subscription', 'id'), access_version: 1
    )
    expect(event.state).to eq('processed')
    expect(Autonomia::Store::Activation.count).to eq(0)
    expect(Autonomia::Store::Entitlement.count).to eq(0)
  end

  it 'does not apply a processed event again' do
    intent
    event = deliver!(payload)
    updated_at = intent.reload.updated_at
    described_class.perform_now(event.id)
    expect(intent.reload.updated_at).to eq(updated_at)
  end

  it 'ignores older subscription stream versions' do
    intent.update!(access_version: 3, state: 'payment_pending')
    deliver!(payload)
    expect(intent.reload).to have_attributes(access_version: 3, state: 'payment_pending', checkout_session_id: nil)
  end

  it 'does not correlate another buyer to the local intent' do
    intent
    payload['data']['buyer']['cognitoSub'] = 'other-fictitious-buyer'
    deliver!(payload)
    expect(intent.reload.state).to eq('reconciling')
  end

  it 'does not correlate another namespace to the local intent' do
    intent
    payload['namespace']['installationId'] = 'other-installation'
    deliver!(payload)
    expect(intent.reload.state).to eq('reconciling')
  end

  it 'does not correlate a different plan price or replace known checkout identifiers' do
    intent.update!(checkout_session_id: SecureRandom.uuid)
    deliver!(payload)
    expect(intent.reload.state).to eq('reconciling')

    payload['eventId'] = SecureRandom.uuid
    payload['data']['checkoutSessionId'] = intent.checkout_session_id
    payload['data']['subscription']['planPriceId'] = SecureRandom.uuid
    deliver!(payload)
    expect(intent.reload.state).to eq('reconciling')
  end

  it 'rechecks checkout identifiers after acquiring the intent lock' do
    existing_id = SecureRandom.uuid
    allow(Autonomia::Store::CheckoutIntent).to receive(:find_by).with(id: payload.dig('data', 'checkoutIntentId')).and_return(intent)
    allow(intent).to receive(:with_lock).and_wrap_original do |lock, &block|
      Autonomia::Store::CheckoutIntent.find(intent.id).update!(checkout_session_id: existing_id)
      lock.call(&block)
    end
    deliver!(payload)
    expect(intent.reload).to have_attributes(checkout_session_id: existing_id, state: 'reconciling')
  end

  it 'keeps an unpaid confirmation blocked instead of declaring checkout completed' do
    intent
    payload['data']['subscription']['status'] = 'unpaid'
    payload['data']['subscription']['access']['allowed'] = false
    deliver!(payload)
    expect(intent.reload).to have_attributes(state: 'reconciling', access_version: 1)
    expect(Autonomia::Store::Entitlement.count).to eq(0)
  end

  it 'does not invent an intent for a renewal with no initial checkout correlation' do
    payload['data']['checkoutIntentId'] = nil
    payload['data']['checkoutSessionId'] = nil
    expect(deliver!(payload).state).to eq('processed')
    expect(Autonomia::Store::CheckoutIntent.count).to eq(0)
  end

  it 'keeps the inbox pending if applying an event fails so it can be retried' do
    data = fixture.fetch('entitlementsSnapshotEvent')
    event = Autonomia::Store::Event.create!(id: data.fetch('eventId'), body_sha256: Digest::SHA256.hexdigest(data.to_json), payload: data)
    allow(Autonomia::Store::Projection).to receive(:apply!).and_raise(ActiveRecord::StatementInvalid, 'fictitious database failure')
    expect { described_class.perform_now(event.id) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(event.reload).to have_attributes(state: 'pending', processed_at: nil)
  end
end
