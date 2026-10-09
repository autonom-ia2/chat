require 'rails_helper'

RSpec.describe Instagram::Testers::BrowserOperations do
  subject(:operations) { described_class.new(store: store) }

  let(:store) { Instagram::Testers::BrowserOperationStore.new }
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:configuration) { instance_double(Instagram::Testers::Configuration, ensure_available!: nil, enabled?: true, app_id: '10001') }
  let(:installation) { 'a' * 64 }
  let(:target_id) { '17841400000000001' }
  let(:key) { "instagram_testers:invite:10001:#{target_id}:outcome" }
  let(:selection) do
    { 'account_id' => account.id.to_s, 'actor_id' => administrator.id.to_s, 'app_id' => '10001', 'id' => target_id,
      'installation' => installation, 'username' => 'demo_company' }
  end
  let(:claimed) do
    queued = store.enqueue(action: 'invite', account_id: account.id, actor_id: administrator.id, app_id: '10001',
                           installation: installation, selection: selection)
    store.claim(id: queued.fetch('id'), request_id: queued.fetch('request_id'))
  end
  let(:captured_at) { Time.current.utc.iso8601(3) }
  let(:permit) do
    claimed.slice('id', 'request_id', 'claim').merge('captured_at' => captured_at, 'target_id' => target_id,
                                                     'username' => 'demo_company', 'status' => 'absent')
  end
  let(:completion) do
    claimed.slice('id', 'request_id', 'claim').merge('type' => 'browser_operation', 'operation' => 'complete',
                                                     'action' => 'invite', 'captured_at' => captured_at,
                                                     'target_id' => target_id)
  end
  let(:other_generation) { "unknown:#{SecureRandom.uuid}" }

  around do |example|
    with_modified_env INSTAGRAM_TESTER_COORDINATION_REDIS_URL: nil,
                      INSTAGRAM_TESTER_COORDINATION_EPOCH: nil,
                      INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE: nil do
      example.run
    end
  end

  before do
    Redis::Alfred.delete(key)
    allow(Instagram::Testers::BrowserOperationStore).to receive(:runtime_enabled?).and_return(true)
    allow(Instagram::Testers::Configuration).to receive(:new).and_return(configuration)
    allow(Instagram::Testers::OauthBinding).to receive(:installation).and_return(installation)
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    Redis::Alfred.with do |connection|
      allow(connection.redis).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([1, 0])
    end
    claimed
  end

  after do
    Redis::Alfred.delete(key)
    Redis::Alfred.delete("#{Instagram::Testers::BrowserOperationStore::PREFIX}:record:#{claimed.fetch('id')}")
    Redis::Alfred.with { |connection| connection.zrem(Instagram::Testers::BrowserOperationStore::QUEUE_KEY, claimed.fetch('id')) }
  end

  def record
    store.result(id: claimed.fetch('id'), account_id: account.id, actor_id: administrator.id)
  end

  def complete_not_written(code)
    operations.complete!(completion.merge('error_code' => code, 'write_started' => false))
  end

  def revoke_inbox_management
    account.account_users.find_by(user: administrator).update!(role: :agent)
  end

  # The store reports the claim once, then loses it, as when a completion
  # closes the record right after the permit's first check.
  def permit_after_lost_claim
    operation = store.claimed(id: claimed.fetch('id'), request_id: claimed.fetch('request_id'), claim: claimed.fetch('claim'))
    store_double = instance_double(Instagram::Testers::BrowserOperationStore)
    calls = 0
    allow(store_double).to receive(:claimed) do
      calls += 1
      raise Instagram::Testers::BrowserOperationStore::Rejected, 'busy' if calls > 1

      operation
    end
    described_class.new(store: store_double).invite_permit(permit)
  end

  describe '#invite_permit' do
    it 'claims this generation and permits the write' do
      expect(operations.invite_permit(permit)).to include(decision: 'write', status: 'absent')
      expect(Redis::Alfred.get(key)).to eq("unknown:#{claimed.fetch('claim')}")
    end

    it 'returns noop without a write when the invitation is already pending' do
      Redis::Alfred.set(key, "pending:#{SecureRandom.uuid}")
      expect(operations.invite_permit(permit)).to include(decision: 'noop', status: 'pending')
    end

    it 'refuses another generation that is still unknown' do
      Redis::Alfred.set(key, other_generation)
      expect { operations.invite_permit(permit) }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
      expect(Redis::Alfred.get(key)).to eq(other_generation)
    end

    it 'leaves no marker when the operation is no longer claimed after claim!' do
      expect { permit_after_lost_claim }.to raise_error(Instagram::Testers::BrowserOperationStore::Rejected, 'busy')
      expect(Redis::Alfred.get(key)).to be_nil
    end

    it 'keeps the original rejection when the late release cannot reach Redis' do
      allow(Instagram::Testers::CoordinationRedis).to receive(:delete_if_equals).and_raise(Redis::TimeoutError)
      expect { permit_after_lost_claim }.to raise_error(Instagram::Testers::BrowserOperationStore::Rejected, 'busy')
    end

    it 'leaves no marker when a not-written completion lands between the claimed check and claim!' do
      completed = false
      allow(store).to receive(:claimed).and_wrap_original do |original, **arguments|
        operation = original.call(**arguments)
        unless completed
          completed = true
          complete_not_written('meta_unavailable')
        end
        operation
      end

      expect { operations.invite_permit(permit) }.to raise_error(Instagram::Testers::BrowserOperationStore::Rejected)
      expect(Redis::Alfred.get(key)).to be_nil
      expect(record).to include('state' => 'failed', 'error_code' => 'invite_not_sent')
    end
  end

  describe '#complete! for invite' do
    it 'moves its own unknown marker to pending after a confirmed write' do
      operations.invite_permit(permit)
      operations.complete!(completion.merge('status' => 'pending', 'invited' => true, 'write_started' => true))
      expect(Redis::Alfred.get(key)).to eq("pending:#{claimed.fetch('claim')}")
      expect(record).to include('state' => 'ready', 'status' => 'pending', 'invited' => true)
    end

    it 'keeps the marker when the write started and its outcome is unknown' do
      operations.invite_permit(permit)
      operations.complete!(completion.merge('error_code' => 'invite_unknown', 'write_started' => true))
      expect(Redis::Alfred.get(key)).to eq("unknown:#{claimed.fetch('claim')}")
      expect(record).to include('state' => 'failed', 'error_code' => 'invite_unknown')
    end

    it 'releases its own marker when Meta rejects the write' do
      operations.invite_permit(permit)
      operations.complete!(completion.merge('error_code' => 'invite_rejected', 'write_started' => true))
      expect(Redis::Alfred.get(key)).to be_nil
      expect(record).to include('state' => 'failed', 'error_code' => 'invite_rejected')
    end

    %w[meta_unavailable meta_session_expired proxy_unavailable operator_required].each do |code|
      it "reports a provably unsent #{code} as invite_not_sent and releases its own marker" do
        operations.invite_permit(permit)
        complete_not_written(code)
        expect(Redis::Alfred.get(key)).to be_nil
        expect(record).to include('state' => 'failed', 'error_code' => 'invite_not_sent')
      end
    end

    it 'keeps invite_unknown for a permit denied by another generation' do
      Redis::Alfred.set(key, other_generation)
      complete_not_written('invite_unknown')
      expect(Redis::Alfred.get(key)).to eq(other_generation)
      expect(record).to include('state' => 'failed', 'error_code' => 'invite_unknown')
    end

    it 'keeps the selection reset code when nothing was written' do
      operations.invite_permit(permit)
      complete_not_written('invalid_selection')
      expect(Redis::Alfred.get(key)).to be_nil
      expect(record).to include('state' => 'failed', 'error_code' => 'invalid_selection')
    end

    it 'reports invite_unknown when its own marker cannot be released' do
      operations.invite_permit(permit)
      allow(Instagram::Testers::CoordinationRedis).to receive(:delete_if_equals).and_raise(Redis::TimeoutError)
      complete_not_written('meta_unavailable')
      expect(record).to include('state' => 'failed', 'error_code' => 'invite_unknown')
    end

    it 'releases its own marker before a failed execution context closes the record' do
      operations.invite_permit(permit)
      revoke_inbox_management
      complete_not_written('meta_unavailable')
      expect(Redis::Alfred.get(key)).to be_nil
      expect(record).to include('state' => 'failed', 'error_code' => 'forbidden')
    end

    it 'never releases another generation when the execution context fails' do
      Redis::Alfred.set(key, other_generation)
      revoke_inbox_management
      complete_not_written('meta_unavailable')
      expect(Redis::Alfred.get(key)).to eq(other_generation)
      expect(record).to include('state' => 'failed', 'error_code' => 'forbidden')
    end

    it 'releases a marker created after the first release by releasing again after closing' do
      allow(store).to receive(:complete).and_wrap_original do |original, **arguments|
        # A late permit claims between the first release and the close.
        Instagram::Testers::InvitationOutcome.new(app_id: '10001', target_id: target_id).claim!(token: claimed.fetch('claim'))
        original.call(**arguments)
      end
      complete_not_written('meta_unavailable')
      expect(Redis::Alfred.get(key)).to be_nil
    end

    it 'keeps the marker when the completion payload cannot be trusted' do
      operations.invite_permit(permit)
      operations.complete!(completion.merge('captured_at' => 10.minutes.from_now.utc.iso8601(3),
                                            'error_code' => 'meta_unavailable', 'write_started' => false))
      expect(Redis::Alfred.get(key)).to eq("unknown:#{claimed.fetch('claim')}")
      expect(record).to include('state' => 'failed', 'error_code' => 'meta_unavailable')
    end
  end
end
