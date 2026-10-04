require 'rails_helper'

RSpec.describe Instagram::Testers::OauthBinding do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:configuration) { instance_double(Instagram::Testers::Configuration, app_id: '10001', ensure_available!: nil) }
  let(:selection) { instance_double(Instagram::Testers::Selection) }
  let(:client) { instance_double(Instagram::Testers::Client) }
  let(:target) do
    { 'id' => '17841400000000001', 'username' => 'demo_company', 'app_id' => '10001', 'account_id' => account.id.to_s,
      'actor_id' => actor.id.to_s, 'installation' => described_class.installation }
  end
  let(:payload) do
    { 'tester_selection' => target, 'installation' => described_class.installation, 'state_version' => described_class::STATE_VERSION,
      'sub' => account.id, 'actor_id' => actor.id, 'iat' => Time.current.to_i, 'exp' => 15.minutes.from_now.to_i, 'jti' => SecureRandom.uuid }
  end

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example') { example.run }
  end

  before do
    allow(Instagram::Testers::Configuration).to receive(:new).with(account_id: account.id).and_return(configuration)
    allow(Instagram::Testers::Selection).to receive(:new).with(account_id: account.id, actor_id: actor.id, app_id: '10001').and_return(selection)
    allow(Instagram::Testers::RateLimiter).to receive(:check!)
    allow(Instagram::Testers::Client).to receive(:new).with(configuration: configuration).and_return(client)
    allow(selection).to receive(:verify).with('signed-synthetic-selection').and_return(target)
  end

  it 'rechecks acceptance and preserves all signed actor context before generating an OAuth state' do
    expect(client).to receive(:status).with(target['id']).and_return('accepted')
    expect(client).not_to receive(:invite)
    expect(described_class.prepare(token: 'signed-synthetic-selection', account_id: account.id, actor_id: actor.id)).to eq(target)
  end

  %w[absent pending].each do |status|
    it "does not continue OAuth for #{status}" do
      allow(client).to receive(:status).and_return(status)
      expect { described_class.prepare(token: 'signed-synthetic-selection', account_id: account.id, actor_id: actor.id) }
        .to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
  end

  it 'claims an expiring selected state only once' do
    expect(described_class.claim!(payload)).to eq(account)
    expect { described_class.claim!(payload) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
  end

  it 'claims a legacy state without any tester configuration or flag and rejects its replay' do
    state = payload.except('tester_selection')
    expect(Instagram::Testers::Configuration).not_to receive(:new)
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false', 'INSTAGRAM_TESTER_SESSION_NAMESPACE' => nil) do
      expect(described_class.claim!(state)).to eq(account)
      expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
  end

  it 'rejects another installation and old in-flight states before consuming a nonce' do
    state = payload
    expect(Redis::Alfred).not_to receive(:set)
    with_modified_env('FRONTEND_URL' => 'https://hub2you.example') do
      expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
    expect { described_class.claim!(state.except('state_version')) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
  end

  it 'rejects removed membership before consuming the nonce' do
    state = payload
    account.account_users.find_by!(user: actor).destroy!
    expect(Redis::Alfred).not_to receive(:set)
    expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end

  it 'rejects lost inbox_manage permission before consuming the nonce' do
    state = payload
    account.account_users.find_by!(user: actor).update!(role: :agent)
    expect(Redis::Alfred).not_to receive(:set)
    expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end

  it 'does not authorize a revoked permission from an already populated Rails query cache' do
    state = payload
    Account.cache do
      cached_account = Account.find_by(id: account.id)
      cached_member = cached_account.account_users.find_by(user_id: actor.id)
      expect(cached_member).to be_administrator

      # Keep the old read cached, reproducing a write from another request.
      AccountUser.uncached(dirties: false) do
        AccountUser.find_by!(account_id: account.id, user_id: actor.id).update!(role: :agent)
      end
      stale_member = Account.find_by(id: account.id).account_users.find_by(user_id: actor.id)
      expect(stale_member).to be_administrator
      expect { described_class.authorize!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
    end
  end

  it 'rejects an actor belonging only to a different account' do
    other_actor = create(:user, account: create(:account), role: :administrator)
    state = payload.except('tester_selection').merge('actor_id' => other_actor.id)
    expect(Redis::Alfred).not_to receive(:set)
    expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end

  it 'rejects a suspended account' do
    state = payload
    account.suspended!
    expect(Redis::Alfred).not_to receive(:set)
    expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end

  it 'rejects selection context from a different actor or account' do
    state = payload
    expect(Redis::Alfred).not_to receive(:set)
    %w[actor_id account_id installation].each do |key|
      bad_selection = target.merge(key => 'other')
      expect { described_class.claim!(state.merge('tester_selection' => bad_selection)) }
        .to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
  end

  it 'rejects wrong parent app, malformed selection and missing nonce' do
    state = payload
    expect(Redis::Alfred).not_to receive(:set)
    [state.merge('tester_selection' => target.merge('app_id' => '10002')),
     state.merge('tester_selection' => target.merge('id' => 12_345)), state.except('jti')].each do |invalid|
      expect { described_class.claim!(invalid) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
  end

  it 'rejects expired, future-issued or excessive validity before consuming the nonce' do
    state = payload
    expect(Redis::Alfred).not_to receive(:set)
    [state.merge('iat' => 16.minutes.ago.to_i, 'exp' => 1.minute.ago.to_i),
     state.merge('iat' => 1.minute.from_now.to_i), state.merge('exp' => 16.minutes.from_now.to_i)].each do |invalid|
      expect { described_class.claim!(invalid) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
  end
end
