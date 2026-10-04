require 'rails_helper'

RSpec.describe Instagram::Testers::OauthBinding do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: ['inbox_manage']) }
  let(:payload) do
    { 'sub' => account.id, 'actor_id' => actor.id, 'installation' => described_class.installation, 'state_version' => described_class::STATE_VERSION,
      'iat' => Time.current.to_i, 'exp' => 15.minutes.from_now.to_i, 'jti' => SecureRandom.uuid }
  end

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example', 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false') { example.run }
  end

  before do
    account.enable_features!('channel_instagram')
    account.disable_features!('instagram_assisted_onboarding')
    account.account_users.find_by!(user: actor).update!(custom_role: role)
  end

  it 'accepts an agent with the real Enterprise inbox_manage permission' do
    expect(described_class.claim!(payload)).to eq(account)
  end

  it 'rejects a denied Instagram channel even with the real custom permission before consuming the nonce' do
    account.disable_features!('channel_instagram')
    expect(Redis::Alfred).not_to receive(:set)
    expect { described_class.claim!(payload) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end

  it 'rejects revocation of the custom permission before consuming its nonce' do
    state = payload
    role.update!(permissions: ['inbox_view'])
    expect(Redis::Alfred).not_to receive(:set)
    expect { described_class.claim!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end

  it 'rechecks the custom permission after the initial claim' do
    state = payload
    described_class.claim!(state)
    role.update!(permissions: ['inbox_view'])
    expect { described_class.authorize!(state) }.to(raise_error { |error| expect(error.code).to eq('forbidden') })
  end
end
