require 'rails_helper'

RSpec.describe 'Autonomia::AuthController', type: :request do
  let(:frontend_url) { 'https://agents.autonomia.site' }
  let(:issuer_url) { 'https://auth.autonomia.site' }
  let(:callback_url) { "#{frontend_url}/auth/autonomia/callback" }
  let(:sso_env) do
    {
      FRONTEND_URL: frontend_url,
      AUTONOMIA_AUTH_ISSUER: issuer_url,
      AUTONOMIA_AUTH_CLIENT_ID: 'talkai',
      AUTONOMIA_AUTH_REDIRECT_URI: callback_url
    }
  end

  describe 'GET /auth/autonomia' do
    it 'redirects to Autonomia Identity with a short session state and PKCE challenge' do
      with_modified_env sso_env do
        get '/auth/autonomia'
      end

      redirect = URI.parse(response.location)
      params = Rack::Utils.parse_query(redirect.query)

      expect(redirect.to_s).to start_with("#{issuer_url}/login?")
      expect(params['client_id']).to eq('talkai')
      expect(params['redirect_uri']).to eq(callback_url)
      expect(params['response_type']).to eq('code')
      expect(params['code_challenge']).to be_present
      expect(params['code_challenge_method']).to eq('S256')
      expect(params['state']).to be_present
      expect(params['state']).to match(/\A[A-Za-z0-9_-]+\z/)
      expect(params['state'].length).to be <= 512
    end

    it 'passes prompt login to Autonomia Identity when requested' do
      with_modified_env sso_env do
        get '/auth/autonomia', params: { prompt: 'login' }
      end

      params = Rack::Utils.parse_query(URI.parse(response.location).query)

      expect(params['prompt']).to eq('login')
    end
  end

  describe 'GET /auth/autonomia/callback' do
    let(:code) { SecureRandom.urlsafe_base64(24) }
    let(:user) { create(:user, email: 'maria+vip@example.com') }
    let(:token) { Autonomia::Sso::Client::Token.new(access_token: 'identity-access-token', id_token: 'identity-id-token') }
    let(:client) { instance_double(Autonomia::Sso::Client) }
    let(:provisioner) { instance_double(Autonomia::Sso::Provisioner, perform: user, post_login_redirect_path: nil) }

    # In production the SSO callback and the frontend share a host, so the
    # redirect to login_page_url is same-host. Drive the request from the
    # FRONTEND_URL host so the spec mirrors that and the redirect is allowed.
    before { host! URI.parse(frontend_url).host }

    it 'exchanges the code when the Rails session state is preserved' do
      with_modified_env sso_env do
        get '/auth/autonomia'
      end

      state = Rack::Utils.parse_query(URI.parse(response.location).query).fetch('state')

      allow(Autonomia::Sso::Client).to receive(:new).and_return(client)
      allow(client).to receive(:exchange_code!).and_return(token)
      allow(client).to receive(:fetch_context!).with('identity-id-token').and_return({})
      allow(Autonomia::Sso::Provisioner).to receive(:new).and_return(provisioner)

      with_modified_env sso_env do
        get '/auth/autonomia/callback', params: { code: code, state: state }
      end

      expect(client).to have_received(:exchange_code!).with(
        code: code,
        redirect_uri: callback_url,
        code_verifier: be_present
      )
      expect(client).to have_received(:fetch_context!).with('identity-id-token')
      expect(Autonomia::Sso::Provisioner).to have_received(:new).with(context: {}, token: token)
      redirect = URI.parse(response.location)
      params = Rack::Utils.parse_query(redirect.query)
      expect(redirect.to_s).to start_with("#{frontend_url}/app/login?")
      # Email must be encoded exactly once; double-encoding would break login for
      # addresses containing '+' or other reserved characters.
      expect(params['email']).to eq(user.email)
      expect(params['sso_auth_token']).to be_present
      expect(params).not_to have_key('redirect_to')
    end

    it 'forwards the provisioner post-login redirect path to the login page' do
      with_modified_env sso_env do
        get '/auth/autonomia'
      end

      state = Rack::Utils.parse_query(URI.parse(response.location).query).fetch('state')
      redirecting_provisioner = instance_double(
        Autonomia::Sso::Provisioner,
        perform: user,
        post_login_redirect_path: '/app/accounts/1/settings/inboxes/new'
      )

      allow(Autonomia::Sso::Client).to receive(:new).and_return(client)
      allow(client).to receive(:exchange_code!).and_return(token)
      allow(client).to receive(:fetch_context!).with('identity-id-token').and_return({})
      allow(Autonomia::Sso::Provisioner).to receive(:new).and_return(redirecting_provisioner)

      with_modified_env sso_env do
        get '/auth/autonomia/callback', params: { code: code, state: state }
      end

      params = Rack::Utils.parse_query(URI.parse(response.location).query)
      expect(params['redirect_to']).to eq('/app/accounts/1/settings/inboxes/new')
    end

    it 'falls back to the access token when Identity does not return an ID token' do
      with_modified_env sso_env do
        get '/auth/autonomia'
      end

      state = Rack::Utils.parse_query(URI.parse(response.location).query).fetch('state')

      allow(Autonomia::Sso::Client).to receive(:new).and_return(client)
      allow(client).to receive(:exchange_code!).and_return(
        Autonomia::Sso::Client::Token.new(access_token: 'identity-access-token')
      )
      allow(client).to receive(:fetch_context!).with('identity-access-token').and_return({})
      allow(Autonomia::Sso::Provisioner).to receive(:new).and_return(provisioner)

      with_modified_env sso_env do
        get '/auth/autonomia/callback', params: { code: code, state: state }
      end

      params = Rack::Utils.parse_query(URI.parse(response.location).query)
      expect(params['email']).to eq(user.email)
      expect(params['sso_auth_token']).to be_present
    end

    it 'rejects an invalid state before exchanging the code' do
      allow(Autonomia::Sso::Client).to receive(:new)

      get '/auth/autonomia/callback', params: { code: code, state: 'invalid-state' }

      expect(Autonomia::Sso::Client).not_to have_received(:new)
      expect(response).to redirect_to(%r{/app/login\?error=autonomia-sso-state$})
    end
  end
end
