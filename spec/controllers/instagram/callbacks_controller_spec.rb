require 'rails_helper'

RSpec.describe Instagram::CallbacksController do
  let(:account) { create(:account) }
  let(:valid_params) { { code: 'valid_code', state: "#{account.id}|valid_token" } }
  let(:error_params) { { error: 'access_denied', error_description: 'User denied access', state: "#{account.id}|valid_token" } }
  let(:oauth_client) { instance_double(OAuth2::Client) }
  let(:auth_code_object) { instance_double(OAuth2::Strategy::AuthCode) }
  let(:access_token) { instance_double(OAuth2::AccessToken, token: 'test_token') }
  let(:long_lived_token_response) { { 'access_token' => 'long_lived_test_token', 'expires_in' => 5_184_000 } }
  let(:user_details) { { 'username' => 'test_user', 'user_id' => '12345', 'id' => '98765' } }
  let(:exception_tracker) { instance_double(ChatwootExceptionTracker) }

  before do
    allow(controller).to receive(:verify_instagram_token).and_return(account.id)
    allow(controller).to receive(:instagram_client).and_return(oauth_client)
    allow(controller).to receive(:base_url).and_return('https://app.chatwoot.com')
    allow(controller).to receive(:account).and_return(account)
    allow(oauth_client).to receive(:auth_code).and_return(auth_code_object)
    allow(controller).to receive(:exchange_for_long_lived_token).and_return(long_lived_token_response)
    allow(controller).to receive(:fetch_instagram_user_details).and_return(user_details)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)
    allow(exception_tracker).to receive(:capture_exception)

    # Stub the exact request format that's being made
    stub_request(:post, 'https://graph.instagram.com/v22.0/12345/subscribed_apps?access_token=long_lived_test_token&subscribed_fields%5B%5D=messages&subscribed_fields%5B%5D=message_reactions&subscribed_fields%5B%5D=messaging_seen')
      .with(
        headers: {
          'Accept' => '*/*',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'User-Agent' => 'Ruby'
        }
      )
      .to_return(status: 200, body: '', headers: {})
  end

  describe '#show' do
    context 'when authorization is successful' do
      before do
        allow(auth_code_object).to receive(:get_token).and_return(access_token)
      end

      it 'creates instagram channel and inbox' do
        expect do
          get :show, params: valid_params
        end.to change(Channel::Instagram, :count).by(1).and change(Inbox, :count).by(1)

        expect(Channel::Instagram.last.access_token).to eq('long_lived_test_token')
        expect(Channel::Instagram.last.instagram_id).to eq('12345')
        expect(Channel::Instagram.last.provider_name).to eq('test_user')
        expect(Inbox.last.name).to eq('test_user')

        expect(Inbox.last.channel.reauthorization_required?).to be false
        expect(response).to redirect_to(app_instagram_inbox_agents_url(account_id: account.id, inbox_id: Inbox.last.id))
      end

      it 'stores the app-scoped id used by Meta deauthorize and data deletion callbacks' do
        get :show, params: valid_params

        expect(Channel::Instagram.last.app_scoped_user_id).to eq('98765')
      end

      it 'updates existing channel with new token' do
        existing_channel = create(:channel_instagram, account: account, instagram_id: '12345', access_token: 'old_token')
        existing_channel.inbox.update!(name: 'Custom Inbox Name')

        expect do
          get :show, params: valid_params
        end.to not_change(Channel::Instagram, :count).and not_change(Inbox, :count)

        existing_channel.reload
        expect(existing_channel.access_token).to eq('long_lived_test_token')
        expect(existing_channel.instagram_id).to eq('12345')
        expect(existing_channel.provider_name).to eq('test_user')
        expect(existing_channel.app_scoped_user_id).to eq('98765')
        expect(existing_channel.inbox.reload.name).to eq('Custom Inbox Name')
        expect(existing_channel.reauthorization_required?).to be false
      end
    end

    context 'when user denies authorization' do
      it 'redirects to error page with authorization error details' do
        get :show, params: error_params

        expect(response).to redirect_to(
          app_new_instagram_inbox_url(
            account_id: account.id,
            error_type: 'access_denied',
            code: 400,
            error_message: 'User denied access'
          )
        )
      end
    end

    context 'when an OAuth error occurs' do
      before do
        oauth_error = OAuth2::Error.new(
          OpenStruct.new(
            body: { error_type: 'OAuthException', code: 400, error_message: 'Invalid OAuth code' }.to_json,
            status: 400
          )
        )
        allow(auth_code_object).to receive(:get_token).and_raise(oauth_error)
      end

      it 'handles OAuth errors and redirects to error page' do
        get :show, params: valid_params

        expected_url = app_new_instagram_inbox_url(
          account_id: account.id,
          error_type: 'OAuthException',
          code: 400,
          error_message: 'Invalid OAuth code'
        )
        expect(response).to redirect_to(expected_url)
      end
    end

    context 'when a standard error occurs' do
      before do
        allow(auth_code_object).to receive(:get_token).and_raise(StandardError.new('Unknown error'))
      end

      it 'handles standard errors and redirects to error page' do
        get :show, params: valid_params

        expected_url = app_new_instagram_inbox_url(
          account_id: account.id,
          error_type: 'StandardError',
          code: 500,
          error_message: 'Unknown error'
        )
        expect(response).to redirect_to(expected_url)
      end
    end
  end

  describe 'selected tester OAuth binding' do
    let(:selection) { { 'id' => '17841400000000001', 'username' => 'test_user', 'app_id' => '10001' } }
    let(:bound_state) { controller.generate_instagram_token(account.id, nil, tester_selection: selection) }
    let(:synthetic_session) do
      { cookie: 'synthetic=fixture', user_agent: 'Synthetic Client', user_id: '12345',
        fb_dtsg: 'synthetic-dtsg', lsd: 'synthetic-lsd', jazoest: '1234' }
    end

    around do |example|
      with_modified_env('INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true', 'INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS' => account.id.to_s,
                        'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
                        'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic app', 'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003',
                        'INSTAGRAM_TESTER_SESSION_JSON' => synthetic_session.to_json) { example.run }
    end

    before do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return('synthetic_secret')
      allow(GlobalConfig).to receive(:get_value).and_call_original
      allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return(false)
      allow(controller).to receive(:verify_instagram_token).and_call_original
      allow(auth_code_object).to receive(:get_token).and_return(access_token)
    end

    it 'creates the selected profile while keeping all three identifiers distinct' do
      get :show, params: { code: 'valid_code', state: bound_state }
      expect(Channel::Instagram.last.instagram_id).to eq('12345')
      expect(Channel::Instagram.last.app_scoped_user_id).to eq('98765')
      expect(Channel::Instagram.last.provider_name).to eq('test_user')
      expect(response).to redirect_to(app_instagram_inbox_agents_url(account_id: account.id, inbox_id: Inbox.last.id))
    end

    it 'rejects another profile before any channel or inbox writes and webhook subscription' do
      user_details['username'] = 'different_user'
      expect(Channel::Instagram).not_to receive(:create!)
      expect(Channel::Instagram).not_to receive(:find_by)
      expect do
        get :show, params: { code: 'valid_code', state: bound_state }
      end.to not_change(Channel::Instagram, :count).and not_change(Inbox, :count)
      expect(response.location).to include('error_type=invalid_selection')
    end

    it 'does not replace an existing token when the selected username differs' do
      channel = create(:channel_instagram, account: account, instagram_id: '12345', access_token: 'old_token')
      user_details['username'] = 'different_user'
      get :show, params: { code: 'valid_code', state: bound_state }
      expect(channel.reload.access_token).to eq('old_token')
      expect(response.location).to include('error_type=invalid_selection')
    end

    it 'rejects expired or tampered state before exchanging OAuth tokens' do
      signed_state = bound_state
      expect(auth_code_object).not_to receive(:get_token)
      get :show, params: { code: 'valid_code', state: "#{signed_state}tampered" }
      expect(response).to redirect_to('/app')
      travel 15.minutes + 1.second do
        get :show, params: { code: 'valid_code', state: signed_state }
        expect(response).to redirect_to('/app')
      end
    end

    it 'rejects replay before another token exchange or write' do
      signed_state = bound_state
      expect(auth_code_object).to receive(:get_token).once.and_return(access_token)
      get :show, params: { code: 'valid_code', state: signed_state }
      get :show, params: { code: 'valid_code', state: signed_state }
      expect(Channel::Instagram.where(account: account).count).to eq(1)
      expect(response.location).to include('error_type=invalid_selection')
    end

    it 'sanitizes denied authorization without changing the legacy error contract' do
      get :show, params: { state: bound_state, error: 'synthetic-error', error_description: 'synthetic-sensitive-description' }
      expect(response.location).to include('error_type=authorization_error')
      expect(response.location).not_to include('synthetic-sensitive-description')
    end

    it 'sanitizes a real truncated token-exchange response before logging, tracking or channel writes' do
      allow(controller).to receive(:exchange_for_long_lived_token).and_call_original
      allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_ID', nil).and_return('synthetic-client')
      marker = 'synthetic-private-response-marker'
      query = { grant_type: 'ig_exchange_token', client_secret: 'synthetic_secret',
                access_token: 'test_token', client_id: 'synthetic-client' }
      stub_request(:get, 'https://graph.instagram.com/access_token').with(query: query)
                                                                    .to_return(status: 200, body: "{\"access_token\":\"#{marker}\"")
      expect(Rails.logger).not_to receive(:error)
      expect(ChatwootExceptionTracker).not_to receive(:new)
      expect do
        get :show, params: { code: 'valid_code', state: bound_state }
      end.to not_change(Channel::Instagram, :count).and not_change(Inbox, :count)
      expect(response.location).to include('error_type=meta_unavailable')
      expect(response.location).not_to include(marker)
    end

    it 'sanitizes provider exceptions for the selected flow' do
      allow(auth_code_object).to receive(:get_token).and_raise(StandardError, 'synthetic-sensitive-provider-data')
      get :show, params: { code: 'valid_code', state: bound_state }
      expect(response.location).to include('error_type=meta_unavailable')
      expect(response.location).not_to include('synthetic-sensitive-provider-data')
    end
  end
end
