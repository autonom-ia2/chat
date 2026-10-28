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

      # Seus posts (#2199): o cartão "Libere seu Instagram" reautoriza a mesma caixa pedindo também
      # instagram_business_manage_insights. Só ali, e só com a flag: o pedido global de escopos não muda.
      describe 'escopo extra de Seus posts' do
        let(:channel) { create(:channel_instagram, account: account) }
        let(:params) { { inbox_id: channel.inbox.id, return_to: 'meta_ads', purpose: 'meta_ads_organico' } }

        def scopes
          Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query).fetch('scope').split(',')
        end

        it 'pede instagram_business_manage_insights e volta para Seus posts' do
          account.enable_features!('meta_ads_organico')

          post "/api/v1/accounts/#{account.id}/instagram/authorization", params: params,
                                                                         headers: administrator.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(scopes).to eq(Instagram::IntegrationHelper::REQUIRED_SCOPES + ['instagram_business_manage_insights'])
          state = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query).fetch('state')
          payload = JWT.decode(state, 'synthetic_secret', true, algorithm: 'HS256').first
          expect(payload).to include('inbox_id' => channel.inbox.id, 'return_to' => 'meta_ads', 'purpose' => 'meta_ads_organico')
        end

        it 'agente sem integration_manage, recusa' do
          account.enable_features!('meta_ads_organico')

          post "/api/v1/accounts/#{account.id}/instagram/authorization", params: params,
                                                                         headers: agent.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unauthorized)
          expect(response.parsed_body).not_to have_key('url')
        end

        it 'com a flag desligada, recusa' do
          post "/api/v1/accounts/#{account.id}/instagram/authorization", params: params,
                                                                         headers: administrator.create_new_auth_token, as: :json

          expect(response).not_to have_http_status(:success)
          expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
        end

        it 'purpose fora da lista, recusa' do
          account.enable_features!('meta_ads_organico')

          post "/api/v1/accounts/#{account.id}/instagram/authorization", params: params.merge(purpose: 'qualquer'),
                                                                         headers: administrator.create_new_auth_token, as: :json

          expect(response.parsed_body).to eq('error_code' => 'invalid_selection')
        end

        it 'reautorizar a caixa pelo lugar de sempre não pede o escopo extra' do
          account.enable_features!('meta_ads_organico')

          post "/api/v1/accounts/#{account.id}/instagram/authorization", params: { inbox_id: channel.inbox.id, return_to: 'inbox' },
                                                                         headers: administrator.create_new_auth_token, as: :json

          expect(scopes).to eq(Instagram::IntegrationHelper::REQUIRED_SCOPES)
        end
      end
    end
  end
end
