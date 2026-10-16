require 'rails_helper'

RSpec.describe Autonomia::Store::RecoverySweepJob do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:namespace) { fixture.fetch('entitlementsResponse').fetch('namespace') }
  let(:intent) do
    Autonomia::Store::CheckoutIntent.create!(
      user: create(:super_admin), account: create(:account), buyer_subject: 'fictitious-buyer',
      installation_id: namespace.fetch('installationId'), product_catalog_item_id: namespace.fetch('productCatalogItemId'),
      client_intent: SecureRandom.uuid, payload: fixture.fetch('checkoutRequest'), state: 'reconciling', next_recovery_at: 1.minute.ago
    )
  end
  let(:activation) do
    Autonomia::Store::Activation.create!(
      user: intent.user, account: intent.account, buyer_subject: intent.buyer_subject,
      installation_id: intent.installation_id, product_catalog_item_id: intent.product_catalog_item_id,
      service_subscription_id: SecureRandom.uuid, service_catalog_item_id: SecureRandom.uuid, feature_key: 'prospecting',
      resource_id: intent.account_id.to_s, metric_key: 'feature_activations', operation_intent: SecureRandom.uuid,
      occurred_at: Time.current, next_recovery_at: 1.minute.ago
    )
  end
  let(:event) do
    payload = fixture.fetch('subscriptionUpdatedEvent')
    Autonomia::Store::Event.create!(id: payload.fetch('eventId'), payload: payload, body_sha256: Digest::SHA256.hexdigest(payload.to_json),
                                    next_recovery_at: 1.minute.ago)
  end
  let(:command) do
    Autonomia::Store::SubscriptionCommand.create!(
      user: intent.user, buyer_subject: intent.buyer_subject, installation_id: intent.installation_id,
      product_catalog_item_id: intent.product_catalog_item_id, service_subscription_id: SecureRandom.uuid,
      client_intent: SecureRandom.uuid, command_action: 'schedule', expected_version: 1, next_recovery_at: 1.minute.ago
    )
  end

  around do |example|
    with_modified_env('FINANCIAL_STORE_INSTALLATION_ID' => namespace.fetch('installationId'),
                      'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => namespace.fetch('productCatalogItemId')) { example.run }
  end

  it 'recovers persisted work without creating a checkout or activation' do
    intent
    activation
    event
    expect { described_class.perform_now }.to have_enqueued_job(Autonomia::Store::CheckoutRecoveryJob).with(intent.id)
    expect(Autonomia::Store::ActivationJob).to have_been_enqueued.with(activation.id)
    expect(Autonomia::Store::EventJob).to have_been_enqueued.with(event.id)
    expect(intent.reload.next_recovery_at).to be > Time.current
    expect(activation.reload.operation_intent).to eq(activation.operation_intent)
    expect(Autonomia::Store::Activation.count).to eq(1)
    expect(Autonomia::Store::CheckoutIntent.count).to eq(1)
  end

  it 'does not enqueue the same batch twice before its next recovery time' do
    activation
    2.times { described_class.perform_now }
    expect(Autonomia::Store::ActivationJob).to have_been_enqueued.exactly(:once)
  end

  it 'recovers a lost enqueue after the scheduling interval' do
    intent
    allow(Autonomia::Store::CheckoutRecoveryJob).to receive(:perform_later).and_raise('fictitious enqueue failure')
    expect { described_class.perform_now }.to raise_error('fictitious enqueue failure')
    expect(intent.reload.state).to eq('reconciling')
    allow(Autonomia::Store::CheckoutRecoveryJob).to receive(:perform_later).and_call_original
    travel 6.minutes do
      expect { described_class.perform_now }.to have_enqueued_job(Autonomia::Store::CheckoutRecoveryJob).with(intent.id)
    end
  end

  it 'respects a live activation lease but resumes after it expires' do
    activation.update!(processing_token: SecureRandom.uuid, processing_at: Time.current)
    expect { described_class.perform_now }.not_to have_enqueued_job(Autonomia::Store::ActivationJob)
    travel 4.minutes do
      expect { described_class.perform_now }.to have_enqueued_job(Autonomia::Store::ActivationJob).with(activation.id)
    end
  end

  it 'uses a slower interval for ready projection refreshes' do
    activation.update!(state: 'ready')
    freeze_time do
      described_class.perform_now
      expect(activation.reload.next_recovery_at).to eq(15.minutes.from_now)
    end
  end

  it 'recovers a pending subscription command without replacing its original intent' do
    original = command.client_intent
    expect { described_class.perform_now }.to have_enqueued_job(Autonomia::Store::SubscriptionCommandJob).with(command.id)
    expect(command.reload.client_intent).to eq(original)
    expect(command.state).to eq('pending')
  end

  it 'respects command leases and excludes terminal commands' do
    command.update!(processing_at: Time.current, processing_token: SecureRandom.uuid)
    expect { described_class.perform_now }.not_to have_enqueued_job(Autonomia::Store::SubscriptionCommandJob)
    command.update!(processing_at: nil, state: 'confirmed')
    expect { described_class.perform_now }.not_to have_enqueued_job(Autonomia::Store::SubscriptionCommandJob)
  end

  it 'recovers an expired checkout only after explicit reconciliation was requested' do
    intent.update!(state: 'expired')
    expect { described_class.perform_now }.not_to have_enqueued_job(Autonomia::Store::CheckoutRecoveryJob)
    intent.update!(reconciliation_requested: true)
    expect { described_class.perform_now }.to have_enqueued_job(Autonomia::Store::CheckoutRecoveryJob).with(intent.id)
  end

  it 'bounds each queue and lets the next batch advance without starving behind prior rows' do
    intent
    21.times do
      Autonomia::Store::CheckoutIntent.create!(intent.attributes.except('id', 'client_intent').merge('client_intent' => SecureRandom.uuid))
    end
    described_class.perform_now
    expect(Autonomia::Store::CheckoutRecoveryJob).to have_been_enqueued.exactly(20).times
    described_class.perform_now
    expect(Autonomia::Store::CheckoutRecoveryJob).to have_been_enqueued.exactly(22).times
  end

  it 'does not recover terminal operations or processed events' do
    intent.update!(state: 'completed')
    activation.update!(state: 'disabled')
    event.update!(state: 'processed')
    expect { described_class.perform_now }.not_to have_enqueued_job
  end

  it 'does not process another installation' do
    intent.update!(installation_id: 'other-installation')
    activation.update!(installation_id: 'other-installation')
    event.update!(payload: event.payload.deep_merge('namespace' => { 'installationId' => 'other-installation' }))
    expect { described_class.perform_now }.not_to have_enqueued_job
  end

  it 'does nothing when the installation has no store namespace' do
    intent
    with_modified_env('FINANCIAL_STORE_INSTALLATION_ID' => '') do
      expect { described_class.perform_now }.not_to have_enqueued_job
    end
  end
end
