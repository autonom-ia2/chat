require 'rails_helper'

RSpec.describe Instagram::Testers::Invitation do
  subject(:invitation) { described_class.new(client: client, app_id: '10001', target_id: target_id) }

  let(:target_id) { '17841400000000001' }
  let(:client) { instance_double(Instagram::Testers::Client) }
  let(:key) { "instagram_testers:invite:10001:#{target_id}" }

  before do
    Redis::Alfred.delete("#{key}:lock")
    Redis::Alfred.delete("#{key}:outcome")
  end

  after do
    Redis::Alfred.delete("#{key}:lock")
    Redis::Alfred.delete("#{key}:outcome")
  end

  %w[pending accepted].each do |status|
    it "does not send another invite for #{status}" do
      allow(client).to receive(:status).with(target_id).and_return(status)
      expect(client).not_to receive(:invite)
      expect(invitation.perform).to eq(status: status, invited: false)
    end
  end

  it 'checks status before the invite and suppresses a double submit during role propagation' do
    expect(client).to receive(:status).with(target_id).ordered.and_return('absent')
    expect(client).to receive(:invite).with(target_id).ordered.and_return(true)
    expect(invitation.perform).to eq(status: 'pending', invited: true)
    allow(client).to receive(:status).with(target_id).and_return('absent')
    expect(invitation.perform).to eq(status: 'pending', invited: false)
  end

  it 'retains an ambiguous write and reconciles status without blindly repeating the POST' do
    allow(client).to receive(:status).with(target_id).and_return('absent')
    expect(client).to receive(:invite).once.and_raise(Instagram::Testers::Error.new('invite_unknown'))
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
    expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
    allow(client).to receive(:status).with(target_id).and_return('pending')
    expect(invitation.perform).to eq(status: 'pending', invited: false)
  end

  it 'preserves an uncertain marker on request cancellation after sending starts' do
    allow(client).to receive(:status).and_return('absent')
    allow(client).to receive(:invite).and_raise(Interrupt, 'Synthetic cancellation')
    expect { invitation.perform }.to raise_error(Interrupt)
    expect(Redis::Alfred.get("#{key}:outcome")).to start_with('unknown:')
    expect(Redis::Alfred.get("#{key}:lock")).to be_nil
  end

  it 'releases only the lock token it still owns' do
    allow(client).to receive(:status) do
      Redis::Alfred.set("#{key}:lock", 'replacement-token', ex: described_class::LOCK_TTL)
      'accepted'
    end
    invitation.perform
    expect(Redis::Alfred.get("#{key}:lock")).to eq('replacement-token')
  end

  it 'serializes concurrent submissions across accounts sharing the parent app' do
    entered = Queue.new
    release = Queue.new
    allow(client).to receive(:status) do
      entered << true
      release.pop
      'absent'
    end
    expect(client).to receive(:invite).once.and_return(true)
    first = Thread.new { invitation.perform }
    entered.pop
    second = described_class.new(client: client, app_id: '10001', target_id: target_id)
    expect { second.perform }.to(raise_error { |error| expect(error.code).to eq('busy') })
    release << true
    expect(first.value).to eq(status: 'pending', invited: true)
  ensure
    release << true if release
    first&.join
  end

  it 'allows another deliberate attempt only after an explicit provider rejection' do
    allow(client).to receive(:status).and_return('absent')
    allow(client).to receive(:invite).and_raise(Instagram::Testers::Error.new('invite_rejected'))
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_rejected') })
    expect(Redis::Alfred.get("#{key}:outcome")).to be_nil
    allow(client).to receive(:invite).and_return(true)
    expect(invitation.perform).to eq(status: 'pending', invited: true)
  end

  it 'never sends an invite when the status request fails' do
    allow(client).to receive(:status).and_raise(Instagram::Testers::Error.new('unknown_status'))
    expect(client).not_to receive(:invite)
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('unknown_status') })
  end

  it 'does not send if another worker atomically claims the outcome despite a stale lock' do
    allow(client).to receive(:status).and_return('absent')
    allow(Instagram::Testers::CoordinationRedis).to receive(:get).and_call_original
    allow(Instagram::Testers::CoordinationRedis).to receive(:get).with("#{key}:outcome").and_return(nil)
    Redis::Alfred.set("#{key}:outcome", 'unknown:another-generation', ex: described_class::OUTCOME_TTL)
    expect(client).not_to receive(:invite)
    expect { invitation.perform }.to(raise_error { |error| expect(error.code).to eq('invite_unknown') })
  end

  it 'never sends an invite if persisting the unknown claim fails' do
    allow(client).to receive(:status).and_return('absent')
    allow(Instagram::Testers::CoordinationRedis).to receive(:set).and_call_original
    allow(Instagram::Testers::CoordinationRedis).to receive(:set).with("#{key}:outcome", kind_of(String), nx: true, ex: described_class::OUTCOME_TTL)
                                                                 .and_raise(Redis::BaseError, 'Synthetic claim persistence failure')
    expect(client).not_to receive(:invite)
    expect { invitation.perform }.to raise_error do |error|
      expect(error.code).to eq('invite_unknown')
      expect(error.cause).to be_nil
    end
    expect(Redis::Alfred.get("#{key}:lock")).to be_nil
  end
end
