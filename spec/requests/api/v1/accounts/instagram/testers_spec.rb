require 'rails_helper'
require 'delegate'

RSpec.describe 'Instagram tester onboarding', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/instagram/testers" }
  let(:headers) { administrator.create_new_auth_token }
  let(:client) { instance_double(Instagram::Testers::Client) }
  let(:candidate) { { id: '17841400000000001', username: 'demo_company', name: 'Synthetic company', avatar_url: nil } }
  let(:session) do
    { cookie: 'synthetic=fixture', user_agent: 'Synthetic Client', user_id: '12345',
      fb_dtsg: 'synthetic-dtsg', lsd: 'synthetic-lsd', jazoest: '1234' }
  end
  let(:settings) do
    { 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true', 'INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => account.id.to_s,
      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
      'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003', 'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic app',
      'FRONTEND_URL' => 'https://autonomia.example',
      'INSTAGRAM_TESTER_SESSION_JSON' => session.to_json }
  end
  let(:token) do
    Instagram::Testers::Selection.new(account_id: account.id, actor_id: administrator.id, app_id: '10001').issue(candidate)
  end

  around { |example| with_modified_env(settings) { example.run } }

  before do
    account.enable_features!(:channel_instagram, :instagram_assisted_onboarding)
    allow(Instagram::Testers::Client).to receive(:new).and_return(client)
    allow(GlobalConfig).to receive(:get_value).and_call_original
    allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return(false)
  end

  it 'requires authentication before any provider request' do
    get "#{path}/configuration"
    expect(response).to have_http_status(:unauthorized)
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'requires inbox_manage even for reads' do
    agent = create(:user, account: account, role: :agent)
    get "#{path}/search", params: { username: 'demo_company' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq('error_code' => 'forbidden')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'preserves account isolation before configuration or provider access' do
    outsider = create(:user, account: create(:account), role: :administrator)
    get "#{path}/configuration", headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'keeps the feature off unless both flag and account allowlist permit access' do
    with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'false') do
      get "#{path}/configuration", headers: headers
      expect(response.parsed_body).to include('enabled' => false, 'available' => false, 'app_name' => nil)
      get "#{path}/search", params: { username: 'demo_company' }, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error_code' => 'not_enabled')
    end
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'exposes unavailable configuration safely without treating it as absent' do
    with_modified_env('INSTAGRAM_TESTER_SESSION_JSON' => '') do
      get "#{path}/configuration", headers: headers
      expect(response.parsed_body).to include('enabled' => true, 'available' => false)
      post "#{path}/status", params: { selection_token: token }, headers: headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error_code' => 'meta_unavailable')
    end
  end

  it 'returns signed selections from search and normalizes the request' do
    expect(client).to receive(:search).with('demo_company').and_return([candidate])
    expect(client).not_to receive(:invite)
    get "#{path}/search", params: { username: ' @Demo_Company ' }, headers: headers
    expect(response).to have_http_status(:ok)
    result = response.parsed_body.fetch('results').first
    expect(result).to include('id' => candidate[:id], 'username' => candidate[:username])
    selected = Instagram::Testers::Selection.new(account_id: account.id, actor_id: administrator.id, app_id: '10001')
    expect(selected.verify(result.fetch('selection_token'))).to include('id' => candidate[:id])
  end

  it 'rejects malformed input and unsigned target IDs before provider access' do
    expect(client).not_to receive(:invite)
    get "#{path}/search", params: { username: ['demo_company'] }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_username')
    post "#{path}/invite", params: { id: candidate[:id] }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
  end

  it 'checks status using the signed selected ID without mutation' do
    expect(client).to receive(:status).with(candidate[:id]).and_return('accepted')
    expect(client).not_to receive(:invite)
    post "#{path}/status", params: { selection_token: token }, headers: headers, as: :json
    expect(response.parsed_body).to eq('status' => 'accepted')
  end

  invalid_tokens = [nil, [], { id: '17841400000000001' }, true, 123, '', 'x' * 4097]
  %w[status invite].each do |action|
    invalid_tokens.each do |invalid_token|
      it "rejects a #{invalid_token.class} token of size #{invalid_token.to_s.size} for #{action} before constructing the provider client" do
        post "#{path}/#{action}", params: { selection_token: invalid_token }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
        expect(Instagram::Testers::Client).not_to have_received(:new)
      end
    end
  end

  it 'rejects a selection issued for a different account' do
    other_token = Instagram::Testers::Selection.new(account_id: create(:account).id, actor_id: administrator.id, app_id: '10001').issue(candidate)
    post "#{path}/status", params: { selection_token: other_token }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'rejects a selection issued for a different actor' do
    another_admin = create(:user, account: account, role: :administrator)
    expect(client).not_to receive(:status)
    post "#{path}/status", params: { selection_token: token }, headers: another_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
  end

  it 'preserves the server-side incident guardrail' do
    allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return('true')
    post "#{path}/invite", params: { selection_token: token }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq('error_code' => 'forbidden')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'renders safe provider failure codes without raw exception content' do
    allow(client).to receive(:status).and_raise(Instagram::Testers::Error.new('unknown_status'))
    post "#{path}/status", params: { selection_token: token }, headers: headers, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body).to eq('error_code' => 'unknown_status')
  end

  it 'throttles before provider access' do
    allow(Instagram::Testers::RateLimiter).to receive(:check!).and_raise(Instagram::Testers::Error.new('rate_limited'))
    get "#{path}/search", params: { username: 'demo_company' }, headers: headers
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error_code' => 'rate_limited')
    expect(Instagram::Testers::Client).not_to have_received(:new)
  end

  it 'permits an Enterprise custom role with inbox_manage' do
    skip 'Enterprise-only custom role' unless ChatwootApp.enterprise?
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['inbox_manage'])
    user.account_users.find_by(account: account).update!(custom_role: role)
    get "#{path}/configuration", headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['enabled']).to be true
  end

  describe 'authoritative invitation outcome reconciliation' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:outcome_key) { "instagram_testers:invite:10001:#{candidate[:id]}:outcome" }
    let(:roles_url) { 'https://developers.facebook.com/api/graphql/' }
    let(:invite_url) { 'https://developers.facebook.com/apps/10001/async/instagram/roles/add/' }
    let(:absent_body) { { data: { get_app_roles: { app_roles: [] } } }.to_json }
    let(:accepted_body) do
      { data: { get_app_roles: { app_roles: [{ role: 'instagram testers', users: [
        { id: candidate[:id], name: 'Synthetic company', role: 'instagram testers', status: 'CONFIRMED' }
      ] }] } } }.to_json
    end

    let(:aof_commands) { instance_spy(Redis) }

    before do
      allow(aof_commands).to receive(:call).with(['WAITAOF', 1, 0, 2000]).and_return([1, 0])
      allow(Instagram::Testers::CoordinationRedis).to receive(:with).and_wrap_original do |original, &block|
        commands = aof_commands
        original.call do |connection|
          wrapper = SimpleDelegator.new(connection)
          wrapper.define_singleton_method(:redis) { commands }
          block.call(wrapper)
        end
      end
      allow(Instagram::Testers::Client).to receive(:new).and_call_original
      Redis::Alfred.delete(outcome_key)
    end

    after { Redis::Alfred.delete(outcome_key) }

    it 'allows a new invite after status observed acceptance and the provider subsequently removed the role' do
      stub_request(:post, roles_url).to_return(status: 200, body: absent_body).then
                                    .to_return(status: 200, body: accepted_body).then
                                    .to_return(status: 200, body: absent_body)
      invites = stub_request(:post, invite_url).to_return(status: 200, body: '{"payload":{"success":true}}')
      post "#{path}/invite", params: { selection_token: token }, headers: headers, as: :json
      expect(response.parsed_body).to eq('status' => 'pending', 'invited' => true)
      post "#{path}/status", params: { selection_token: token }, headers: headers, as: :json
      expect(response.parsed_body).to eq('status' => 'accepted')
      expect(Redis::Alfred.get(outcome_key)).to be_nil
      post "#{path}/invite", params: { selection_token: token }, headers: headers, as: :json
      expect(response.parsed_body).to eq('status' => 'pending', 'invited' => true)
      expect(invites).to have_been_requested.twice
    end

    it 'blocks the provider POST and retry when the durability command fails' do
      stub_request(:post, roles_url).to_return(status: 200, body: absent_body)
      expect(aof_commands).to receive(:call).with(['WAITAOF', 1, 0, 2000]).once
                                            .and_raise(Redis::CommandError, 'Synthetic unsupported WAITAOF')
      2.times do
        post "#{path}/invite", params: { selection_token: token }, headers: headers, as: :json
        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body).to eq('error_code' => 'invite_unknown')
      end
      expect(Redis::Alfred.get(outcome_key)).to start_with('unknown:')
      expect(a_request(:post, invite_url)).not_to have_been_made
    end

    it 'keeps a timed-out invite guarded through status absent and a retry' do
      stub_request(:post, roles_url).to_return(status: 200, body: absent_body)
      invites = stub_request(:post, invite_url).to_timeout
      post "#{path}/invite", params: { selection_token: token }, headers: headers, as: :json
      expect(response.parsed_body).to eq('error_code' => 'invite_unknown')
      post "#{path}/status", params: { selection_token: token }, headers: headers, as: :json
      expect(response.parsed_body).to eq('status' => 'absent')
      post "#{path}/invite", params: { selection_token: token }, headers: headers, as: :json
      expect(response.parsed_body).to eq('error_code' => 'invite_unknown')
      expect(Redis::Alfred.get(outcome_key)).to start_with('unknown:')
      expect(invites).to have_been_requested.once
    end
  end
end
