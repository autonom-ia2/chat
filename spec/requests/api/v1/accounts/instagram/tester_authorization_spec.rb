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

  it 'keeps legacy authorization free of tester calls with a bound state' do
    post path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    query = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query)
    state = JWT.decode(query.fetch('state'), 'synthetic_secret', true, algorithm: 'HS256').first
    expect(state.keys).to contain_exactly('sub', 'iat', 'actor_id', 'installation', 'state_version', 'exp', 'jti')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'keeps the legacy onboarding return hint when the tester feature is off' do
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
