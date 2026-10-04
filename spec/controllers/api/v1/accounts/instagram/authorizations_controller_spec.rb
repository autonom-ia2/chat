require 'rails_helper'

RSpec.describe 'Instagram Authorization API', type: :request do
  let(:account) { create(:account) }

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example') { example.run }
  end

  before do
    account.enable_features!('channel_instagram')
    account.disable_features!('instagram_assisted_onboarding')
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return('synthetic_secret')
  end

  describe 'POST /api/v1/accounts/{account.id}/instagram/authorization' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/instagram/authorization"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agent' do
        post "/api/v1/accounts/#{account.id}/instagram/authorization",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'rejects an administrator when the Instagram channel is denied' do
        account.disable_features!('channel_instagram')
        expect(OAuth2::Client).not_to receive(:new)
        post "/api/v1/accounts/#{account.id}/instagram/authorization",
             headers: administrator.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq('error_code' => 'forbidden')
      end

      it 'creates a new authorization and returns the redirect url' do
        post "/api/v1/accounts/#{account.id}/instagram/authorization",
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['success']).to be true

        state = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query).fetch('state')
        payload = JWT.decode(state, 'synthetic_secret', true, algorithm: 'HS256').first
        expect(payload['actor_id']).to eq(administrator.id)

        instagram_service = Class.new do
          extend InstagramConcern
          extend Instagram::IntegrationHelper
        end
        frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
        response_url = instagram_service.instagram_client.auth_code.authorize_url(
          {
            redirect_uri: "#{frontend_url}/instagram/callback",
            scope: Instagram::IntegrationHelper::REQUIRED_SCOPES.join(','),
            enable_fb_login: '0',
            force_reauth: 'true',
            response_type: 'code',
            state: state
          }
        )
        expect(response.parsed_body['url']).to eq response_url
      end
    end
  end
end
