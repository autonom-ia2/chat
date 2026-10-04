require 'spec_helper'
require_relative '../../../../config/environment'

RSpec.describe Instagram::Automation::OperatorControl do
  subject(:control) { described_class.new }

  let(:namespace) { 'lina-950-synthetic' }
  let(:root) { "instagram_testers:operator:#{namespace}" }
  let(:data) { {} }
  let(:ttls) { {} }
  let(:connection) { instance_double(Redis) }

  around { |example| with_modified_env('INSTAGRAM_TESTER_SESSION_NAMESPACE' => namespace) { example.run } }

  before do
    allow(Redis::Alfred).to receive(:with).and_yield(connection)
    allow(connection).to receive(:watch).and_yield
    allow(connection).to receive(:unwatch)
    allow(connection).to receive(:get) { |key| data[key] }
    allow(connection).to receive(:ttl) { |key| ttls.fetch(key, -2) }
    allow(connection).to receive(:multi) { |&block|
      block.call(connection)
      ['OK']
    }
    allow(connection).to receive(:set) { |key, value, ex:|
      data[key] = value
      ttls[key] = ex
      'OK'
    }
    allow(Instagram::Testers::CoordinationRedis).to receive(:with).and_raise('unexpected coordination use')
    allow(Instagram::Testers::SessionStore).to receive(:new).and_raise('unexpected session use')
  end

  it 'uses only deterministic dedicated keys and explicit TTL for heartbeat and request' do
    control.heartbeat(state: 'operator_required', control_available: true)
    result = control.enqueue(id: SecureRandom.uuid, actor_id: 42)
    expect(result).to include('action' => 'reconnect', 'state' => 'queued', 'actor_id' => 42)
    expect(Time.iso8601(result.fetch('created_at'))).to be <= Time.current
    expect(Time.iso8601(result.fetch('expires_at'))).to be > Time.current
    expect(control.status.fetch(:manager).fetch('observed_at')).to be_a(String)
    expect(result.fetch('id')).to match(/\A[0-9a-f-]{36}\z/)
    expect(data.keys).to contain_exactly("#{root}:manager", "#{root}:current")
    expect(ttls).to eq("#{root}:manager" => described_class::HEARTBEAT_TTL, "#{root}:current" => described_class::REQUEST_TTL)
  end

  it 'keeps one queued or running request, requires the matching UUID, and permits a fresh explicit retry' do
    control.heartbeat(state: 'operator_required', control_available: true)
    first = control.enqueue(id: SecureRandom.uuid, actor_id: 42)
    expect(control.enqueue(id: SecureRandom.uuid, actor_id: 42)).to eq(first)
    expect { control.claim(SecureRandom.uuid) }.to raise_error(described_class::Rejected)
    expect(control.claim(first.fetch('id'))).to include('state' => 'running')
    expect { control.claim(first.fetch('id')) }.to raise_error(described_class::Rejected)
    expect(control.enqueue(id: SecureRandom.uuid, actor_id: 42)).to include('id' => first.fetch('id'), 'state' => 'running')
    expect(control.complete(first.fetch('id'), 'operator_required')).to include('state' => 'operator_required')
    expect(control.enqueue(id: SecureRandom.uuid, actor_id: 42).fetch('id')).not_to eq(first.fetch('id'))
  end

  it 'fails closed for missing expired unhealthy or malformed heartbeat' do
    expect { control.enqueue(id: SecureRandom.uuid, actor_id: 42) }.to raise_error(described_class::Rejected)
    control.heartbeat(state: 'healthy', control_available: false)
    expect { control.enqueue(id: SecureRandom.uuid, actor_id: 42) }.to raise_error(described_class::Rejected)
    control.heartbeat(state: 'operator_required', control_available: true)
    ttls["#{root}:manager"] = -1
    expect { control.enqueue(id: SecureRandom.uuid, actor_id: 42) }.to raise_error(described_class::Rejected)
    data["#{root}:manager"] = { state: 'operator_required', control_available: true, cookie: 'synthetic' }.to_json
    ttls["#{root}:manager"] = 90
    expect(control.status).to include(operator_required: false, control_available: false)
    expect { control.enqueue(id: SecureRandom.uuid, actor_id: 42) }.to raise_error(described_class::Rejected)
  end

  it 'never accepts secret fields, arbitrary actions or corrupt requests' do
    control.heartbeat(state: 'operator_required', control_available: true)
    data["#{root}:current"] = { id: SecureRandom.uuid, action: 'reconnect', state: 'queued', url: 'synthetic' }.to_json
    ttls["#{root}:current"] = 60
    expect { control.enqueue(id: SecureRandom.uuid, actor_id: 42) }.to raise_error(described_class::Rejected)
    expect(control.status.to_json).not_to include('synthetic')
    expect { control.heartbeat(state: 'healthy', control_available: true) }.to raise_error(described_class::Rejected)
    expect { control.heartbeat(state: 'healthy', control_available: 'false') }.to raise_error(described_class::Rejected)
  end

  it 'completes only the matching running request and preserves unrelated storage' do
    data['unrelated'] = 'preserved'
    control.heartbeat(state: 'operator_required', control_available: true)
    request = control.enqueue(id: SecureRandom.uuid, actor_id: 42)
    expect { control.complete(request.fetch('id'), 'succeeded') }.to raise_error(described_class::Rejected)
    control.claim(request.fetch('id'))
    expect { control.complete(SecureRandom.uuid, 'succeeded') }.to raise_error(described_class::Rejected)
    expect { control.complete(request.fetch('id'), 'succeeded') }.to raise_error(described_class::Rejected)
    expect(control.with_publication(request.fetch('id')) { SecureRandom.uuid }).to match(described_class::UUID)
    expect(control.read.fetch('request')).to include('state' => 'succeeded')
    expect(data['unrelated']).to eq('preserved')
  end

  it 'rejects namespace traversal before any Redis call and sanitizes connection failures' do
    with_modified_env('INSTAGRAM_TESTER_SESSION_NAMESPACE' => '../invalid') do
      expect(described_class.new.status).to include(control_available: false)
    end
    allow(Redis::Alfred).to receive(:with).and_raise(Redis::CannotConnectError, 'synthetic')
    expect(control.status).to include(control_available: false)
    expect { control.enqueue(id: SecureRandom.uuid, actor_id: 42) }.to raise_error(described_class::Rejected, 'operator_channel_unavailable')
  end

  it 'does not refresh TTL on duplicate enqueue or acknowledge an aborted compare-and-set' do
    control.heartbeat(state: 'operator_required', control_available: true)
    request = control.enqueue(id: SecureRandom.uuid, actor_id: 42)
    ttls["#{root}:current"] = 25
    expect(control.enqueue(id: SecureRandom.uuid, actor_id: 42)).to eq(request)
    expect(ttls["#{root}:current"]).to eq(25)
    allow(connection).to receive(:multi).and_return(nil)
    expect { control.claim(request.fetch('id')) }.to raise_error(described_class::Rejected)
    expect(JSON.parse(data.fetch("#{root}:current")).fetch('state')).to eq('queued')
  end

  it 'reports an explicit manager failure using the existing unavailable panel status' do
    control.heartbeat(state: 'failed', control_available: false)
    expect(control.status).to include(manager: include('state' => 'failed', 'control_available' => false, 'observed_at' => be_a(String)),
                                      manager_connectivity: 'unavailable', operator_required: false, control_available: false)
  end

  context 'with bounded running claims' do
    let(:control) { described_class.new }
    let(:connection) { instance_double(Redis) }
    let(:data) { {} }
    let(:namespace) { 'lina-950-lease' }
    let(:now) { Time.iso8601('2026-10-04T10:00:00.000Z') }

    around { |example| with_modified_env('INSTAGRAM_TESTER_SESSION_NAMESPACE' => namespace) { example.run } }

    before do
      allow(Time).to receive(:current).and_return(now)
      allow(Redis::Alfred).to receive(:with).and_yield(connection)
      allow(connection).to receive(:watch).and_yield
      allow(connection).to receive(:unwatch)
      allow(connection).to receive(:get) { |key| data[key] }
      allow(connection).to receive(:ttl).and_return(100)
      allow(connection).to receive(:set) { |key, value, **| data[key] = value }
      allow(connection).to receive(:multi) { |&block|
        block.call(connection)
        ['OK']
      }
      control.heartbeat(state: 'operator_required', control_available: true)
    end

    it 'rejects invalid actor types and preserves controller-provided ID' do
      [nil, '42', 0, -1, 9_007_199_254_740_992].each do |actor|
        expect { control.enqueue(actor_id: actor) }.to raise_error(described_class::Rejected)
      end
      id = SecureRandom.uuid
      expect(control.enqueue(actor_id: 42, id: id)).to include('id' => id, 'actor_id' => 42, 'updated_at' => now.iso8601(3))
    end

    it 'expires a crashed running claim without deleting storage or permitting a late success' do
      request = control.enqueue(actor_id: 42)
      control.claim(request.fetch('id'))
      allow(Time).to receive(:current).and_return(now + 91)
      expect(control.read.fetch('request')).to include('state' => 'failed')
      expect(data.fetch("instagram_testers:operator:#{namespace}:current")).to include('running')
      expect { control.with_publication(request.fetch('id')) { raise 'must not publish' } }.to raise_error(described_class::Rejected)
      expect(control.enqueue(actor_id: 43).fetch('id')).not_to eq(request.fetch('id'))
    end

    it 'renews the running claim only for its matching ID with a real timestamp' do
      request = control.enqueue(actor_id: 42)
      control.claim(request.fetch('id'))
      allow(Time).to receive(:current).and_return(now + 60)
      control.heartbeat(state: 'operator_required', control_available: false, request_id: request.fetch('id'))
      expect(control.read.fetch('request')).to include('expires_at' => (now + 150).iso8601(3), 'updated_at' => (now + 60).iso8601(3))
      expect do
        control.heartbeat(state: 'operator_required', control_available: false, request_id: SecureRandom.uuid)
      end.to raise_error(described_class::Rejected)
    end

    it 'never acknowledges success when the actual publisher or the request CAS fails' do
      request = control.enqueue(actor_id: 42)
      control.claim(request.fetch('id'))
      expect { control.with_publication(request.fetch('id')) { raise 'synthetic failure' } }.to raise_error('synthetic failure')
      expect(control.read.fetch('request')).to include('state' => 'running')
      allow(connection).to receive(:multi).and_return(nil)
      expect { control.with_publication(request.fetch('id')) { SecureRandom.uuid } }.to raise_error(described_class::Rejected)
      expect(control.read.fetch('request')).to include('state' => 'running')
    end

    it 'runs actual SessionStore CAS outside the control WATCH and only then records success' do
      request = control.enqueue(actor_id: 42)
      control.claim(request.fetch('id'))
      watching = false
      allow(connection).to receive(:watch) do |*_keys, &block|
        raise 'nested WATCH' if watching

        watching = true
        result = block.call
        watching = false
        result
      end
      allow(Instagram::Testers::SessionStore).to receive(:new).and_call_original
      allow(Redis::SecureStorage).to receive(:set) { |key, payload, _ttl| data[key] = payload.to_json }
      configuration = Instagram::Automation::SessionPublisher::Snapshot.new(app_id: '10001', business_id: '10002',
                                                                            admin_user_id: '12345', proxy_fingerprint: 'a' * 64)
      store = Instagram::Testers::SessionStore.new(configuration: configuration)
      session = { 'cookie' => 'c_user=12345; xs=synthetic', 'fb_dtsg' => 'synthetic', 'lsd' => 'synthetic', 'jazoest' => '1234',
                  'user_id' => '12345', 'user_agent' => 'Synthetic Browser', 'extra_form' => {} }
      version = control.with_publication(request.fetch('id')) do
        expect(watching).to be(false)
        store.publish(session: session, expected_version: nil, captured_at: now.iso8601(3), app_id: '10001', business_id: '10002',
                      proxy_fingerprint: 'a' * 64)
      end
      pointer = JSON.parse(data.fetch("instagram_testers:session:#{namespace}:pointer"))
      expect(pointer).to include('version' => version, 'state' => 'active')
      expect(control.read.fetch('request')).to include('state' => 'succeeded')
    end

    it 'does not overwrite a request completed by another actor while publication was in flight' do
      request = control.enqueue(actor_id: 42)
      control.claim(request.fetch('id'))
      expect do
        control.with_publication(request.fetch('id')) do
          control.complete(request.fetch('id'), 'failed')
          SecureRandom.uuid
        end
      end.to raise_error(described_class::Rejected)
      expect(control.read.fetch('request')).to include('state' => 'failed')
    end

    it 'reports unknown for stale or invalid dates, including impossible calendar days' do
      key = "instagram_testers:operator:#{namespace}:manager"
      ['2026-02-31T10:00:00.000Z', 'invalid', (now - 961).iso8601(3), (now + 6).iso8601(3)].each do |stamp|
        data[key] = { state: 'operator_required', control_available: true, observed_at: stamp }.to_json
        expect(control.status).to include(manager_connectivity: 'unknown', control_available: false)
      end
    end
  end
end
