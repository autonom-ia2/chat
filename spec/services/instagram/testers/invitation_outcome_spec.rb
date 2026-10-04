require 'rails_helper'

RSpec.describe Instagram::Testers::InvitationOutcome do
  subject(:outcome) { described_class.new(app_id: '10001', target_id: '17841400000000001') }

  let(:key) { 'instagram_testers:invite:10001:17841400000000001:outcome' }

  before { Redis::Alfred.delete(key) }
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
end
