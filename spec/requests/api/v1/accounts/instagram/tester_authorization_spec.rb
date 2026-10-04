require 'rails_helper'

RSpec.describe 'Instagram authorization with tester selection', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/instagram/authorization" }
  let(:headers) { administrator.create_new_auth_token }
  let(:client) { instance_double(Instagram::Testers::Client) }
  let(:candidate) { { id: '17841400000000001', username: 'demo_company' } }
  let(:selection_token) do
    Instagram::Testers::Selection.new(account_id: account.id, actor_id: administrator.id, app_id: '10001').issue(candidate)
  end
  let(:session) do
    { cookie: 'synthetic=fixture', user_agent: 'Synthetic Client', user_id: '12345',
      fb_dtsg: 'synthetic-dtsg', lsd: 'synthetic-lsd', jazoest: '1234' }
  end

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example', 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true',
                      'INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => account.id.to_s,
                      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
                      'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic app', 'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003',
                      'INSTAGRAM_TESTER_SESSION_JSON' => session.to_json) { example.run }
  end

  before do
    account.enable_features!(:channel_instagram, :instagram_assisted_onboarding)
    allow(Instagram::Testers::Client).to receive(:new).and_return(client)
    allow(GlobalConfig).to receive(:get_value).and_call_original
    allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return(false)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return('synthetic_secret')
  end

  it 'rechecks accepted status and signs the selected profile into the OAuth state' do
    expect(client).to receive(:status).with(candidate[:id]).and_return('accepted')
    expect(client).not_to receive(:invite)
    post path, params: { tester_selection_token: selection_token, return_to: 'onboarding' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    query = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query)
    state = JWT.decode(query.fetch('state'), 'synthetic_secret', true, algorithm: 'HS256').first
    expect(state['tester_selection']).to eq('id' => candidate[:id], 'username' => candidate[:username], 'app_id' => '10001',
                                            'account_id' => account.id.to_s, 'actor_id' => administrator.id.to_s,
                                            'installation' => Instagram::Testers::OauthBinding.installation)
    expect(state['exp'] - state['iat']).to eq(15.minutes.to_i)
    expect(state['return_to']).to eq('onboarding')
    expect(query['scope']).to eq(Instagram::IntegrationHelper::REQUIRED_SCOPES.join(','))
  end

  it 'does not issue a bound OAuth URL for pending status' do
    allow(client).to receive(:status).and_return('pending')
    post path, params: { tester_selection_token: selection_token }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
  end

  it 'rejects an invalid optional token instead of silently downgrading to legacy OAuth' do
    post path, params: { tester_selection_token: nil }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  [[], { id: '17841400000000001' }, true, 123, '', 'x' * 4097].each do |invalid_token|
    it "rejects a supplied #{invalid_token.class} token of size #{invalid_token.to_s.size} without falling back to legacy OAuth" do
      post path, params: { tester_selection_token: invalid_token }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
      expect(Instagram::Testers::Client).not_to have_received(:new)
    end
  end

  it 'keeps account-OFF legacy authorization free of tester infrastructure with a bound state' do
    account.disable_features!(:instagram_assisted_onboarding)
    expect(Instagram::Testers::Configuration).not_to receive(:new)
    expect(Instagram::Testers::OauthBinding).not_to receive(:prepare)
    post path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    query = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query)
    state = JWT.decode(query.fetch('state'), 'synthetic_secret', true, algorithm: 'HS256').first
    expect(state.keys).to contain_exactly('sub', 'iat', 'actor_id', 'installation', 'state_version', 'exp', 'jti')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'keeps the legacy onboarding return hint when the tester feature is off' do
    account.disable_features!('instagram_assisted_onboarding')
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example', 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false') do
      post path, params: { return_to: 'onboarding' }, headers: headers, as: :json
    end

    expect(response).to have_http_status(:ok)
    query = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query)
    state = JWT.decode(query.fetch('state'), 'synthetic_secret', true, algorithm: 'HS256').first
    expect(state.keys).to contain_exactly('sub', 'iat', 'return_to', 'actor_id', 'installation', 'state_version', 'exp', 'jti')
    expect(state['return_to']).to eq('onboarding')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'rejects a new connection without selection while ON before consulting tester infrastructure' do
    expect(Instagram::Testers::Client).not_to receive(:new)
    expect(Instagram::Testers::SessionStore).not_to receive(:new)
    post path, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
  end

  it 'blocks an ON account when the global kill-switch is off or the legacy allowlist excludes it' do
    [{ 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false' },
     { 'INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => (account.id + 1).to_s }].each do |settings|
      with_modified_env(settings) do
        post path, params: { tester_selection_token: selection_token }, headers: headers, as: :json
      end
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error_code' => 'not_enabled')
    end
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'blocks ON authorization when tester infrastructure is unavailable without legacy fallback' do
    with_modified_env('INSTAGRAM_TESTER_SESSION_JSON' => '') do
      post path, params: { tester_selection_token: selection_token }, headers: headers, as: :json
    end
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('error_code' => 'meta_unavailable')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'keeps account OFF direct even with an invalid tester token and missing tester infrastructure' do
    account.disable_features!(:instagram_assisted_onboarding)
    expect(Instagram::Testers::Configuration).not_to receive(:new)
    expect(Instagram::Testers::OauthBinding).not_to receive(:prepare)
    post path, params: { tester_selection_token: nil }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'allows explicit reauthorization of an existing account Instagram inbox without tester infrastructure' do
    inbox = create(:channel_instagram, account: account).inbox
    expect(Instagram::Testers::Configuration).not_to receive(:new)
    expect(Instagram::Testers::OauthBinding).not_to receive(:prepare)
    post path, params: { inbox_id: inbox.id, return_to: 'inbox' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    query = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query)
    state = JWT.decode(query.fetch('state'), 'synthetic_secret', true, algorithm: 'HS256').first
    expect(state['inbox_id']).to eq(inbox.id)
    expect(state['instagram_id']).to eq(inbox.channel.instagram_id)
    expect(state['return_to']).to eq('inbox')
    expect(state).not_to have_key('tester_selection')
  end

  it 'rejects a return hint alone as a reauthorization bypass' do
    post path, params: { return_to: 'inbox' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
  end

  it 'rejects foreign, non-Instagram and missing inboxes as a reauthorization bypass' do
    foreign = create(:channel_instagram).inbox
    other_channel = create(:inbox, account: account)
    [foreign.id, other_channel.id, 0, [], '123', true].each do |inbox_id|
      post path, params: { inbox_id: inbox_id, return_to: 'inbox' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
    end
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'rejects ambiguous reauthorization with selection or onboarding return hint' do
    inbox = create(:channel_instagram, account: account).inbox
    [{ inbox_id: inbox.id, return_to: 'onboarding' },
     { inbox_id: inbox.id, return_to: 'inbox', tester_selection_token: selection_token }].each do |params|
      post path, params: params, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'blocks Meta-restricted authorization in both account flows before provider access' do
    allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return(true)
    expect(Instagram::Testers::Client).not_to receive(:new)
    expect(OAuth2::Client).not_to receive(:new)
    [true, false].each do |enabled|
      enabled ? account.enable_features!(:instagram_assisted_onboarding) : account.disable_features!(:instagram_assisted_onboarding)
      post path, params: { tester_selection_token: selection_token }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error_code' => 'forbidden')
    end
  end

  it 'rejects an account without the Instagram channel in both modes before tester or OAuth access' do
    account.disable_features!('channel_instagram')
    expect(Instagram::Testers::Configuration).not_to receive(:new)
    expect(OAuth2::Client).not_to receive(:new)
    [true, false].each do |enabled|
      enabled ? account.enable_features!(:instagram_assisted_onboarding) : account.disable_features!(:instagram_assisted_onboarding)
      post path, params: { tester_selection_token: selection_token }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'rejects reauthorization for an agent without inbox_manage' do
    inbox = create(:channel_instagram, account: account).inbox
    agent = create(:user, account: account, role: :agent)
    membership = account.account_users.find_by!(user: agent)
    expect(membership.permission_granted?('inbox_manage')).to be false
    expect(Instagram::Testers::OauthBinding).not_to receive(:prepare)
    post path, params: { inbox_id: inbox.id, return_to: 'inbox' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'reconciles an accepted provider role during the actual OAuth preparation path' do
    allow(Instagram::Testers::Client).to receive(:new).and_call_original
    outcome = Instagram::Testers::InvitationOutcome.new(app_id: '10001', target_id: candidate[:id])
    outcome.claim!
    outcome.pending!
    stub_request(:post, 'https://developers.facebook.com/api/graphql/').to_return(status: 200, body: {
      data: { get_app_roles: { app_roles: [{ role: 'instagram testers', users: [{ id: candidate[:id], status: 'CONFIRMED' }] }] } }
    }.to_json)
    post path, params: { tester_selection_token: selection_token }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['success']).to be true
    expect(outcome.state).to be_nil
  ensure
    Redis::Alfred.delete("instagram_testers:invite:10001:#{candidate[:id]}:outcome")
  end
end
