require 'rails_helper'

RSpec.describe Instagram::IntegrationHelper do
  include described_class

  let(:client_secret) { 'synthetic_secret' }
  let(:current_time) { Time.current }
  let(:selected) do
    { 'id' => '17841400000000001', 'username' => 'demo_company', 'app_id' => '10001', 'account_id' => '16',
      'actor_id' => '2', 'installation' => Instagram::Testers::OauthBinding.installation }
  end

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example', 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false',
                      'INSTAGRAM_TESTER_SESSION_NAMESPACE' => nil) { example.run }
  end

  before do
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return(client_secret)
    freeze_time
  end

  it 'signs account, actor, installation, expiration and nonce for legacy OAuth with testers disabled' do
    payload = instagram_token_payload(generate_instagram_token(16, actor_id: 2))
    expect(payload).to include('sub' => 16, 'actor_id' => 2, 'state_version' => 2,
                               'installation' => Instagram::Testers::OauthBinding.installation, 'iat' => current_time.to_i)
    expect(payload['exp'] - payload['iat']).to eq(15.minutes.to_i)
    expect(payload['jti'].length).to eq(36)
    expect(payload).not_to have_key('tester_selection')
  end

  it 'preserves selection context and onboarding return hint in the signed state' do
    token = generate_instagram_token(16, 'onboarding', actor_id: 2, tester_selection: selected)
    expect(instagram_token_payload(token)['tester_selection']).to eq(selected)
    expect(instagram_token_return_to(token)).to eq('onboarding')
    expect(verify_instagram_token(token)).to eq(16)
  end

  it 'issues different nonces for reauthorization of the same account and actor' do
    first = instagram_token_payload(generate_instagram_token(16, actor_id: 2))
    second = instagram_token_payload(generate_instagram_token(16, actor_id: 2))
    expect(first['jti']).not_to eq(second['jti'])
  end

  it 'rejects state from another installation even with the same AppSecret and local IDs' do
    token = generate_instagram_token(16, actor_id: 2)
    with_modified_env('FRONTEND_URL' => 'https://hub2you.example') do
      expect(verify_instagram_token(token)).to be_nil
    end
  end

  it 'refuses in-flight states issued before the binding rollout instead of downgrading' do
    [{ sub: 16, iat: current_time.to_i },
     { sub: 16, iat: current_time.to_i, exp: 15.minutes.from_now.to_i, jti: SecureRandom.uuid,
       tester_installation: 'synthetic-old-namespace', tester_selection: selected }].each do |payload|
      token = JWT.encode(payload, client_secret, 'HS256')
      expect(verify_instagram_token(token)).to be_nil
    end
  end

  it 'rejects both legacy and selected states after their validity window' do
    tokens = [generate_instagram_token(16, actor_id: 2), generate_instagram_token(16, actor_id: 2, tester_selection: selected)]
    travel 15.minutes + 1.second do
      tokens.each { |token| expect(verify_instagram_token(token)).to be_nil }
    end
  end

  it 'rejects a token signed with another secret or tampered after issue' do
    token = generate_instagram_token(16, actor_id: 2)
    expect(verify_instagram_token("#{token}tampered")).to be_nil
    other_secret = JWT.encode(token_payload(16, actor_id: 2), 'other-synthetic-secret', 'HS256')
    expect(verify_instagram_token(other_secret)).to be_nil
  end

  it 'rejects blank tokens' do
    expect(verify_instagram_token('')).to be_nil
    expect(verify_instagram_token(nil)).to be_nil
  end

  it 'does not emit a usable state when the configured callback base is missing or invalid' do
    [nil, '', 'https://user:pass@autonomia.example', 'https://autonomia.example?untrusted=1'].each do |url|
      with_modified_env('FRONTEND_URL' => url) do
        expect(generate_instagram_token(16, actor_id: 2)).to be_nil
      end
    end
  end

  it 'normalizes equivalent configured callback bases without using tester namespace or request Host' do
    namespace = Instagram::Testers::OauthBinding.installation
    with_modified_env('FRONTEND_URL' => 'https://AUTONOMIA.example:443/') do
      expect(Instagram::Testers::OauthBinding.installation).to eq(namespace)
    end
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example/other') do
      expect(Instagram::Testers::OauthBinding.installation).not_to eq(namespace)
    end
  end

  context 'when client secret is missing' do
    let(:client_secret) { nil }

    it 'returns nil without issuing a state' do
      expect(generate_instagram_token(16, actor_id: 2)).to be_nil
      expect(verify_instagram_token('any-token')).to be_nil
    end
  end

  it 'sanitizes token generation errors' do
    allow(JWT).to receive(:encode).and_raise(StandardError.new('synthetic-private-token'))
    expect(Rails.logger).to receive(:error).with('Instagram token generation failed')
    expect(generate_instagram_token(16, actor_id: 2)).to be_nil
  end
end
