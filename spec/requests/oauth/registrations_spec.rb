require 'rails_helper'

RSpec.describe 'OAuth Dynamic Client Registration', type: :request do
  let(:registration_params) do
    { client_name: 'ChatGPT', redirect_uris: ['https://chatgpt.com/connector/oauth/callback'] }
  end

  before do
    InstallationConfig.where(name: 'OAUTH_PROVIDER_ENABLED').delete_all
    InstallationConfig.create!(name: 'OAUTH_PROVIDER_ENABLED', value: true)
  end

  after { GlobalConfig.clear_cache }

  describe 'POST /oauth/register' do
    it 'returns 404 when the provider is disabled' do
      InstallationConfig.find_by(name: 'OAUTH_PROVIDER_ENABLED').update!(value: false)

      post '/oauth/register', params: registration_params, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'registers a public client and returns its metadata' do
      post '/oauth/register', params: registration_params, as: :json

      expect(response).to have_http_status(:created)
      application = Doorkeeper::Application.last
      expect(application).to have_attributes(name: 'ChatGPT', confidential: false, secret: nil)
      expect(response.parsed_body).to include(
        'client_id' => application.uid,
        'client_name' => 'ChatGPT',
        'redirect_uris' => ['https://chatgpt.com/connector/oauth/callback'],
        'token_endpoint_auth_method' => 'none',
        'grant_types' => %w[authorization_code refresh_token],
        'response_types' => ['code']
      )
      expect(response.parsed_body).not_to have_key('client_secret')
    end

    it 'registers a public client even when a secret-based method is requested' do
      post '/oauth/register', params: registration_params.merge(token_endpoint_auth_method: 'client_secret_post'), as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['token_endpoint_auth_method']).to eq('none')
      expect(Doorkeeper::Application.last).not_to be_confidential
    end

    it 'limits the client to the scopes it registers' do
      post '/oauth/register', params: registration_params.merge(scope: 'conversations:read'), as: :json

      expect(response.parsed_body['scope']).to eq('conversations:read')
      expect(Doorkeeper::Application.last.scopes.to_a).to eq(['conversations:read'])
    end

    it 'rejects a scope the server does not define' do
      post '/oauth/register', params: registration_params.merge(scope: 'admin'), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_client_metadata')
    end

    it 'rejects a registration without redirect URIs' do
      post '/oauth/register', params: registration_params.except(:redirect_uris), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_redirect_uri')
    end

    it 'rejects a plain HTTP redirect URI' do
      post '/oauth/register', params: registration_params.merge(redirect_uris: ['http://chatgpt.com/callback']), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_redirect_uri')
    end

    it 'rejects a script redirect URI' do
      post '/oauth/register', params: registration_params.merge(redirect_uris: ['javascript:alert(1)']), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(Doorkeeper::Application.count).to eq(0)
    end

    it 'rejects a registration without a client name' do
      post '/oauth/register', params: registration_params.except(:client_name), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_client_metadata')
    end

    it 'cuts a long client name, which the consent screen shows' do
      post '/oauth/register', params: registration_params.merge(client_name: 'A' * 500), as: :json

      expect(response).to have_http_status(:created)
      expect(Doorkeeper::Application.last.name.length).to eq(100)
    end

    it 'rejects several redirect URIs packed in one item' do
      packed = Array.new(11) { |index| "https://chatgpt.com/cb/#{index}" }.join("\n")
      post '/oauth/register', params: registration_params.merge(redirect_uris: [packed]), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(Doorkeeper::Application.count).to eq(0)
    end

    it 'rejects more than ten redirect URIs' do
      uris = Array.new(11) { |index| "https://chatgpt.com/cb/#{index}" }
      post '/oauth/register', params: registration_params.merge(redirect_uris: uris), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to eq('invalid_redirect_uri')
      expect(Doorkeeper::Application.count).to eq(0)
    end
  end
end
