require 'spec_helper'
require 'climate_control'

ENV['RAILS_ENV'] ||= 'test'
require_relative '../../../../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?

RSpec.describe Instagram::Testers::InvitationOutcome do
  subject(:outcome) { described_class.new(app_id: '10001', target_id: '17841400000000001') }

  let(:key) { 'instagram_testers:invite:10001:17841400000000001:outcome' }

  around do |example|
    with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: nil,
                      INSTAGRAM_TESTER_COORDINATION_EPOCH: nil,
                      INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: nil do
      example.run
    end
  end

  before do
    Redis::Alfred.delete(key)
    Redis::Alfred.with do |connection|
      allow(connection.redis).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([1, 0])
    end
  end

  after { Redis::Alfred.delete(key) }

  %w[pending accepted].each do |status|
    it "clears an observed generation only after an authoritative #{status} read" do
      outcome.claim!
      outcome.pending!
      expect(outcome.reconcile { status }).to eq(status)
      expect(outcome.state).to be_nil
    end
  end

  it 'preserves an unknown write when the role is still absent' do
    outcome.claim!
    expect(outcome.reconcile { 'absent' }).to eq('absent')
    expect(outcome.state).to eq('unknown')
  end

  it 'releases only its own unknown claim after a proven preflight failure' do
    outcome.claim!
    outcome.release_claim!
    expect(outcome.state).to be_nil
  end

  %w[unknown pending].each do |state|
    it "does not release a newer #{state} generation on an older preflight failure" do
      outcome.claim!
      Redis::Alfred.set(key, "#{state}:newer-generation", ex: described_class::TTL)
      outcome.release_claim!
      expect(Redis::Alfred.get(key)).to eq("#{state}:newer-generation")
    end
  end

  it 'does not clear a newer invitation that began during an older status request' do
    outcome.claim!
    outcome.pending!
    newer = described_class.new(app_id: '10001', target_id: '17841400000000001')
    outcome.reconcile do
      Redis::Alfred.delete(key) # Simulates expiration/removal of the older generation.
      newer.claim!
      'accepted'
    end
    expect(newer.state).to eq('unknown')
  end

  it 'does not recreate a pending marker when status confirmed an in-flight write before its reply' do
    outcome.claim!
    expect(outcome.reconcile { 'accepted' }).to eq('accepted')
    outcome.pending!
    expect(outcome.state).to be_nil
  end

  it 'clears the same generation when its write reply arrives during status lookup' do
    outcome.claim!
    outcome.reconcile do
      outcome.pending!
      'accepted'
    end
    expect(outcome.state).to be_nil
  end

  it 'clears pending in the same generation when EXEC aborts after the unknown comparison' do
    outcome.claim!
    unknown = Redis::Alfred.get(key)
    pending = "pending:#{unknown.partition(':').last}"
    interrupted = false

    Redis::Alfred.with do |connection|
      allow(connection).to receive(:multi).and_wrap_original do |original, &transaction|
        if interrupted
          original.call(&transaction)
        else
          interrupted = true
          expect(connection.get(key)).to eq(unknown)
          connection.set(key, pending, ex: described_class::TTL)
          nil # Redis aborts EXEC when a concurrent write changed the watched value.
        end
      end
      expect(outcome.reconcile { 'accepted' }).to eq('accepted')
      expect(outcome.state).to be_nil
      expect(connection).to have_received(:multi).twice
    end
  end

  %w[unknown pending].each do |state|
    it "preserves a newer #{state} generation created between the two compare-and-delete operations" do
      outcome.claim!
      unknown = Redis::Alfred.get(key)
      pending = "pending:#{unknown.partition(':').last}"
      newer = described_class.new(app_id: '10001', target_id: '17841400000000001')

      expect(Instagram::Testers::CoordinationRedis).to receive(:delete_if_equals).with(key,
                                                                                       unknown).ordered.and_wrap_original do |original, *arguments|
        result = original.call(*arguments)
        newer.claim!
        newer.pending! if state == 'pending'
        result
      end
      expect(Instagram::Testers::CoordinationRedis).to receive(:delete_if_equals).with(key, pending).ordered.and_call_original

      expect(outcome.reconcile { 'accepted' }).to eq('accepted')
      expect(newer.state).to eq(state)
    end
  end

  it 'does not clear a marker when status lookup raises an error' do
    outcome.claim!
    expect { outcome.reconcile { raise Instagram::Testers::Error, 'unknown_status' } }
      .to(raise_error { |error| expect(error.code).to eq('unknown_status') })
    expect(outcome.state).to eq('unknown')
  end

  it 'claims through durable_set with the unchanged 24 hour TTL' do
    expect(Instagram::Testers::CoordinationRedis).to receive(:durable_set).with(key, kind_of(String), ex: 86_400).and_return(true)
    outcome.claim!
  end

  context 'when sending an invitation' do
    let(:client) { instance_double(Instagram::Testers::Client, status: 'absent') }
    let(:invitation) { Instagram::Testers::Invitation.new(client: client, app_id: '10001', target_id: '17841400000000001') }

    after { Redis::Alfred.delete('instagram_testers:invite:10001:17841400000000001:lock') }

    [nil, 'different-epoch-2026'].each do |stored_epoch|
      it 'prevents an invitation with a missing or mismatched remote epoch' do
        remote = MockRedis.new
        remote.set('instagram_tester_coordination:integrity:epoch', stored_epoch) if stored_epoch
        allow(Redis).to receive(:new).and_return(remote)
        Instagram::Testers::CoordinationRedis.instance_variable_set(:@pools, {})
        expect(client).not_to receive(:invite)
        with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: 'rediss://:synthetic@coordination.invalid:6379/0',
                          INSTAGRAM_TESTER_COORDINATION_EPOCH: 'synthetic-epoch-2026',
                          INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: nil do
          expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('meta_unavailable') })
          expect(remote.get('instagram_tester_coordination:integrity:epoch')).to eq(stored_epoch)
          expect(remote.get("instagram_tester_coordination:#{key}")).to be_nil
        end
      end
    end

    it 'confirms fsync before invoking the invitation transport' do
      Redis::Alfred.with do |connection|
        expect(connection.redis).to receive(:call).with(['WAITAOF', 1, 0, 2000]).ordered.and_return([1, 0])
        expect(client).to receive(:invite).ordered.and_yield.and_return(true)
        expect(invitation.perform).to eq(status: 'pending', invited: true)
      end
    end

    it 'retains unknown and prevents the invitation and its retry when fsync times out' do
      Redis::Alfred.with do |connection|
        allow(connection.redis).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([0, 0])
        expect(client).not_to receive(:invite)
        expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
        expect(outcome.state).to eq('unknown')
        expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
        expect(outcome.state).to eq('unknown')
      end
    end

    [Redis::TimeoutError, Redis::CommandError].each do |failure|
      it 'retains the marker and prevents transport on failed or unsupported WAITAOF' do
        Redis::Alfred.with do |connection|
          allow(connection.redis).to receive(:call).and_raise(failure, 'synthetic failure')
          expect(client).not_to receive(:invite)
          expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
          expect(outcome.state).to eq('unknown')
        end
      end
    end
  end
end
