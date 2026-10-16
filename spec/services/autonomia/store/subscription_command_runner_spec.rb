require 'rails_helper'

RSpec.describe Autonomia::Store::SubscriptionCommandRunner do
  let(:client) { instance_double(Autonomia::Financial::StoreLifecycleClient) }
  let(:command) do
    Autonomia::Store::SubscriptionCommand.create!(user: create(:super_admin), buyer_subject: 'fictitious-buyer',
                                                  installation_id: 'example-installation', product_catalog_item_id: SecureRandom.uuid,
                                                  service_subscription_id: SecureRandom.uuid, client_intent: SecureRandom.uuid,
                                                  expected_version: 1, command_action: 'schedule')
  end
  let(:receipt) { { 'command' => { 'idempotencyKey' => command.id }, 'data' => { 'serviceSubscriptionId' => command.service_subscription_id } } }

  before do
    allow(Autonomia::Store::BuyerClient).to receive(:fetch!).with(command,
                                                                  client_class: Autonomia::Financial::StoreLifecycleClient).and_return(client)
    allow(client).to receive(:schedule_cancellation!).and_return(receipt)
    allow(client).to receive(:resume_renewal!).and_return(receipt)
  end

  it 'uses the saved command and version, without releasing any resources' do
    described_class.new(command).run!
    expect(command.reload).to have_attributes(state: 'confirmed', receipt: receipt, processing_token: nil)
    expect(client).to have_received(:schedule_cancellation!).with(command.service_subscription_id,
                                                                  'contractVersion' => 1, 'expectedVersion' => 1, 'idempotencyKey' => command.id)
    expect(Autonomia::Store::Activation.count).to eq(0)
  end

  it 'reuses the exact body after an unknown result and never changes expectedVersion' do
    bodies = []
    allow(client).to receive(:schedule_cancellation!) do |_id, body|
      bodies << body.deep_dup
      raise Autonomia::Financial::StoreClientError.new('TRANSPORT_ERROR', outcome: 'unknown') if bodies.one?

      receipt
    end
    described_class.new(command).run!
    expect(command.reload).to have_attributes(state: 'pending', error_code: 'TRANSPORT_ERROR')
    described_class.new(command).run!
    expect(bodies.size).to eq(2)
    expect(bodies.first).to eq(bodies.last)
    expect(command.reload.state).to eq('confirmed')
  end

  it 'does not reapply a confirmed command' do
    command.update!(state: 'confirmed', receipt: receipt)
    described_class.new(command).run!
    expect(client).not_to have_received(:schedule_cancellation!)
  end

  it 'makes a version conflict terminal rather than silently choosing another version' do
    allow(client).to receive(:schedule_cancellation!).and_raise(Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409))
    described_class.new(command).run!
    expect(command.reload).to have_attributes(state: 'blocked', error_code: 'CONFLICT', expected_version: 1)
    described_class.new(command).run!
    expect(client).to have_received(:schedule_cancellation!).once
  end

  it 'keeps a command pending when refreshable OAuth is temporarily unavailable' do
    allow(Autonomia::Store::BuyerClient).to receive(:fetch!).and_raise(Autonomia::Financial::StoreClientError.new('UNAUTHORIZED', status: 401))
    described_class.new(command).run!
    expect(command.reload).to have_attributes(state: 'pending', error_code: 'UNAUTHORIZED')
    expect(client).not_to have_received(:schedule_cancellation!)
  end

  it 'does not steal an active lease' do
    token = SecureRandom.uuid
    command.update!(processing_token: token, processing_at: Time.current)
    described_class.new(command).run!
    expect(command.reload.processing_token).to eq(token)
    expect(client).not_to have_received(:schedule_cancellation!)
  end

  it 'supports reversal with its own explicit command' do
    command.update!(command_action: 'resume')
    described_class.new(command).run!
    expect(client).to have_received(:resume_renewal!).with(command.service_subscription_id, command.financial_payload)
    expect(client).not_to have_received(:schedule_cancellation!)
  end

  it 'prevents a second pending command for the same owner contract at the database boundary' do
    duplicate = command.dup
    duplicate.client_intent = SecureRandom.uuid
    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
