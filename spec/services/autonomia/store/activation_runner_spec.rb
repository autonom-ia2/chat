require 'rails_helper'

RSpec.describe Autonomia::Store::ActivationRunner do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/checkout.v1.json').read) }
  let(:account) { create(:account) }
  let(:user) { create(:super_admin) }
  let(:namespace) { fixture.fetch('entitlementsResponse').fetch('namespace') }
  let(:client) { instance_double(Autonomia::Financial::StoreCheckoutClient) }
  let(:activation) do
    Autonomia::Store::Activation.create!(
      user: user, account: account, installation_id: namespace.fetch('installationId'),
      product_catalog_item_id: namespace.fetch('productCatalogItemId'),
      buyer_subject: fixture.dig('checkoutResponse', 'buyer', 'cognitoSub'),
      service_subscription_id: fixture.dig('reservationResponse', 'reservation', 'serviceSubscriptionId'),
      service_catalog_item_id: fixture.dig('entitlementsResponse', 'data', 'serviceCatalogItemId'),
      feature_key: 'prospecting', resource_id: account.id.to_s, metric_key: 'feature_activations',
      operation_intent: SecureRandom.uuid, occurred_at: Time.current
    )
  end
  let(:reserved) do
    fixture.fetch('reservationResponse').deep_dup.tap do |result|
      result['reservation']['resourceRef'] = activation.resource_ref
      result['reservation']['status'] = 'reserved'
    end
  end
  let(:committed) { reserved.deep_dup.tap { |result| result['reservation']['status'] = 'committed' } }
  let(:snapshot) do
    fixture.fetch('entitlementsResponse').deep_dup.tap do |result|
      result['data']['resourceRef'] = activation.resource_ref
      result['data']['grants'].first['effectiveUntil'] = 1.day.from_now.iso8601
    end
  end

  before do
    create(:account_user, account: account, user: user, role: :administrator)
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).with(user).and_return('fictitious-access')
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return(fixture.dig('checkoutResponse', 'buyer', 'cognitoSub'))
    configuration = instance_double(Autonomia::Financial::StoreConfiguration, namespace: namespace)
    allow(Autonomia::Financial::StoreConfiguration).to receive(:new).and_return(configuration)
    allow(Autonomia::Financial::StoreCheckoutClient).to receive(:new).and_return(client)
    allow(client).to receive(:reserve!).and_return(reserved)
    allow(client).to receive(:commit!).and_return(committed)
    allow(client).to receive(:reservation!).and_return(reserved)
    allow(client).to receive(:entitlements!).and_return(snapshot)
  end

  it 'only makes the feature ready after reserve, commit and a matching confirmed grant' do
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('ready')
    expect(activation.processing_token).to be_nil
    expect(client).to have_received(:reserve!).with(hash_including('quantity' => 1, 'resourceRef' => activation.resource_ref))
    expect(client).to have_received(:commit!).with(activation.reservation_id, 'idempotencyKey' => activation.intent_key('commit'))
    expect(activation.public_payload(snapshot: snapshot['data'])[:available]).to be(true)
  end

  it 'reuses the durable reserve intent and timestamp after a lost provider response' do
    calls = []
    allow(client).to receive(:reserve!) do |body|
      calls << body.deep_dup
      raise Autonomia::Financial::StoreClientError.new('TIMEOUT', outcome: 'unknown') if calls.one?

      reserved
    end
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload.state).to eq('preparing')
    expect(activation.reserve_attempted).to be(true)
    described_class.new(activation).run!
    expect(calls.size).to eq(2)
    expect(calls[0]).to eq(calls[1])
    expect(activation.reload.state).to eq('ready')
  end

  it 'does not grant access while commit is confirmed but entitlement is missing' do
    snapshot['data']['grants'] = []
    snapshot['data']['effectiveAccess'] = 'ended'
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError) { |error|
      expect(error.code).to eq('ENTITLEMENT_PENDING')
    }
    expect(activation.reload.state).to eq('committed')
    expect(activation.public_payload(snapshot: snapshot['data'])[:available]).to be(false)
  end

  it 'does not treat a grant for another subscription as this activation confirmation' do
    snapshot['data']['grants'].first['serviceSubscriptionId'] = SecureRandom.uuid
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload.state).to eq('committed')
  end

  it 'does not override a newer revoked projection with an older granted response' do
    revoked = snapshot.deep_dup
    revoked['accessVersion'] = '2'
    revoked['data']['effectiveAccess'] = 'ended'
    revoked['data']['grants'].first['status'] = 'revoked'
    Autonomia::Store::Projection.apply!(revoked)
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload.state).to eq('committed')
    expect(Autonomia::Store::Entitlement.last.access_version.to_i).to eq(2)
  end

  it 'recovers and releases the same reservation when disable races with reserve' do
    allow(client).to receive(:reserve!) do
      activation.update!(state: 'disabling')
      reserved
    end
    released = reserved.deep_dup
    released['reservation']['status'] = 'released'
    allow(client).to receive(:release!).and_return(released)
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('disabled')
    expect(client).not_to have_received(:commit!)
    expect(client).to have_received(:release!).with(activation.reservation_id, hash_including('idempotencyKey' => activation.intent_key('release')))
  end

  it 'blocks a concurrent runner without removing the first runner lease' do
    token = SecureRandom.uuid
    activation.update!(processing_token: token, processing_at: Time.current)
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError) { |error|
      expect(error.code).to eq('OPERATION_BUSY')
    }
    expect(activation.reload.processing_token).to eq(token)
    expect(client).not_to have_received(:reserve!)
  end

  it 'rejects a beneficiary without administrator membership before reserving capacity' do
    user.account_users.find_by!(account: account).update!(role: :agent)
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(client).not_to have_received(:reserve!)
    expect(activation.reload.state).to eq('preparing')
  end

  it 'keeps access denied when Financial rejects an exhausted capacity limit' do
    allow(client).to receive(:reserve!).and_raise(Autonomia::Financial::StoreClientError.new('USAGE_LIMIT_EXCEEDED', status: 409))
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload).to have_attributes(state: 'preparing', error_code: 'USAGE_LIMIT_EXCEEDED', reservation_id: nil)
    expect(client).not_to have_received(:commit!)
    expect(Autonomia::Store::Entitlement.count).to eq(0)
  end

  it 'replays the same commit after a lost response without reserving capacity again' do
    calls = []
    allow(client).to receive(:commit!) do |id, body|
      calls << [id, body.deep_dup]
      raise Autonomia::Financial::StoreClientError.new('TIMEOUT', outcome: 'unknown') if calls.one?

      committed
    end
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload.state).to eq('reserved')
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('ready')
    expect(client).to have_received(:reserve!).once
    expect(calls.size).to eq(2)
    expect(calls[0]).to eq(calls[1])
  end

  it 'keeps access disabled during release recovery and reuses the release intent' do
    activation.update!(state: 'disabling', reservation_id: committed.dig('reservation', 'id'), reserve_attempted: true)
    released = committed.deep_dup
    released['reservation']['status'] = 'released'
    calls = []
    allow(client).to receive(:release!) do |id, body|
      calls << [id, body.deep_dup]
      raise Autonomia::Financial::StoreClientError.new('TIMEOUT', outcome: 'unknown') if calls.one?

      released
    end
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload.state).to eq('disabling')
    expect(activation.public_payload(snapshot: snapshot['data'])[:available]).to be(false)
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('disabled')
    expect(calls[0]).to eq(calls[1])
    expect(client).not_to have_received(:reserve!)
  end

  it 'marks an expired reservation terminal without blindly committing it' do
    activation.update!(state: 'reserved', reservation_id: reserved.dig('reservation', 'id'))
    allow(client).to receive(:reservation!).and_return(reserved.deep_dup.tap { |result| result['reservation']['status'] = 'expired' })
    described_class.new(activation).run!
    expect(activation.reload).to have_attributes(state: 'failed', error_code: 'RESERVATION_EXPIRED')
    expect(client).not_to have_received(:commit!)
    expect(client).not_to have_received(:reserve!)
  end

  it 'recognizes an already committed reservation after losing its commit response' do
    activation.update!(state: 'reserved', reservation_id: committed.dig('reservation', 'id'))
    allow(client).to receive(:reservation!).and_return(committed)
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('ready')
    expect(client).not_to have_received(:commit!)
    expect(client).not_to have_received(:reserve!)
  end

  it 'does not recreate capacity when a recovered reserve is already expired' do
    allow(client).to receive(:reserve!).and_return(reserved.deep_dup.tap { |result| result['reservation']['status'] = 'expired' })
    activation.update!(reserve_attempted: true)
    described_class.new(activation).run!
    expect(activation.reload).to have_attributes(state: 'failed', error_code: 'RESERVATION_EXPIRED')
    expect(client).to have_received(:reserve!).once
    expect(client).not_to have_received(:commit!)
  end

  it 'synchronizes expired mirrors before a ready snapshot refresh can fail' do
    principal = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Example principal', agent_type: 'custom')
    activation.update!(state: 'ready', feature_key: nil,
                       target: { 'type' => 'agent', 'installationId' => namespace.fetch('installationId'), 'principalAgentId' => principal.id })
    agent = Autonomia::Store::AgentInstance.provision!(activation)
    allow(Autonomia::Store::AgentInstance).to receive(:sync_access!)
    allow(client).to receive(:entitlements!) do
      expect(Autonomia::Store::AgentInstance).to have_received(:sync_access!).with(agent)
      raise Autonomia::Financial::StoreClientError.new('TIMEOUT', outcome: 'unknown')
    end
    expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
    expect(activation.reload.state).to eq('ready')
    expect(agent.reload.deleted?).to be(false)
  end

  it 'rechecks an expiration racing commit409 instead of blindly retrying commit' do
    activation.update!(state: 'reserved', reservation_id: reserved.dig('reservation', 'id'))
    expired = reserved.deep_dup.tap { |result| result['reservation']['status'] = 'expired' }
    allow(client).to receive(:reservation!).and_return(reserved, expired)
    allow(client).to receive(:commit!).and_raise(Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409))
    described_class.new(activation).run!
    expect(activation.reload).to have_attributes(state: 'failed', error_code: 'RESERVATION_EXPIRED')
    expect(client).to have_received(:commit!).once
    expect(client).not_to have_received(:reserve!)
  end

  it 'stops disabling when the authoritative reservation is already expired' do
    activation.update!(state: 'disabling', reservation_id: reserved.dig('reservation', 'id'), reserve_attempted: true)
    allow(client).to receive(:reservation!).and_return(reserved.deep_dup.tap { |result| result['reservation']['status'] = 'expired' })
    allow(client).to receive(:release!)
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('disabled')
    expect(client).not_to have_received(:release!)
    expect(client).not_to have_received(:reserve!)
  end

  it 'recognizes a release that succeeded before its response was lost' do
    activation.update!(state: 'disabling', reservation_id: reserved.dig('reservation', 'id'), reserve_attempted: true)
    allow(client).to receive(:reservation!).and_return(reserved.deep_dup.tap { |result| result['reservation']['status'] = 'released' })
    allow(client).to receive(:release!)
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('disabled')
    expect(client).not_to have_received(:release!)
  end

  it 'rechecks an expiration racing release409 and closes without a second release' do
    activation.update!(state: 'disabling', reservation_id: reserved.dig('reservation', 'id'), reserve_attempted: true)
    expired = reserved.deep_dup.tap { |result| result['reservation']['status'] = 'expired' }
    allow(client).to receive(:reservation!).and_return(reserved, expired)
    allow(client).to receive(:release!).and_raise(Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409))
    described_class.new(activation).run!
    expect(activation.reload.state).to eq('disabled')
    expect(client).to have_received(:release!).once
  end

  context 'with a contracted agent target' do
    let(:principal) { Autonomia::Agents::Agent.create!(account: create(:account), name: 'Example principal', agent_type: 'custom') }

    before do
      activation.update!(feature_key: nil, target: { 'type' => 'agent', 'installationId' => namespace.fetch('installationId'),
                                                     'principalAgentId' => principal.id })
    end

    it 'creates the linked instance only after a matching confirmed grant and does not duplicate on replay' do
      snapshot['data']['grants'] = []
      expect { described_class.new(activation).run! }.to raise_error(Autonomia::Financial::StoreClientError)
      expect(Autonomia::Agents::Agent.where(principal_agent: principal).count).to eq(0)
      snapshot['accessVersion'] = '2'
      snapshot['data']['grants'] = [{ 'serviceSubscriptionId' => activation.service_subscription_id,
                                      'reservationId' => activation.reservation_id, 'status' => 'granted',
                                      'effectiveUntil' => 1.day.from_now.iso8601 }]
      2.times { described_class.new(activation).run! }
      expect(activation.reload.state).to eq('ready')
      expect(activation.agent).to have_attributes(account_id: account.id, principal_agent_id: principal.id)
      expect(Autonomia::Agents::Agent.where(principal_agent: principal).count).to eq(1)
      expect(client).to have_received(:reserve!).once
      expect(client).to have_received(:commit!).once
    end

    it 'rolls back technical creation if checkpoint fails, then resumes the same reservation' do
      allow(Autonomia::Store::AgentInstance).to receive(:provision!).and_wrap_original do |method, record|
        method.call(record)
        raise ActiveRecord::Deadlocked
      end
      expect { described_class.new(activation).run! }.to raise_error(ActiveRecord::Deadlocked)
      expect(activation.reload.state).to eq('committed')
      expect(activation.agent_id).to be_nil
      expect(Autonomia::Agents::Agent.where(principal_agent: principal).count).to eq(0)
      allow(Autonomia::Store::AgentInstance).to receive(:provision!).and_call_original
      described_class.new(activation).run!
      expect(activation.reload.state).to eq('ready')
      expect(client).to have_received(:reserve!).once
      expect(client).to have_received(:commit!).once
    end

    it 'releases the committed slot if the principal disappears while confirmation is in flight' do
      allow(client).to receive(:commit!) do
        principal.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        committed
      end
      released = committed.deep_dup
      released['reservation']['status'] = 'released'
      allow(client).to receive(:release!).and_return(released)
      described_class.new(activation).run!
      expect(activation.reload).to have_attributes(state: 'disabled', error_code: 'AGENT_PRINCIPAL_UNAVAILABLE', agent_id: nil)
      expect(client).to have_received(:release!).once
      expect(Autonomia::Agents::Agent.where(principal_agent: principal)).to be_empty
    end
  end
end
