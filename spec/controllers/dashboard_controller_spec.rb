require 'rails_helper'

describe 'early Autonomia SSO redirect', type: :request do
  let(:sso_env) { { AUTONOMIA_SSO_AUTO_REDIRECT: 'true' } }
  let(:valid_cookie_payload) do
    {
      'access-token' => 'local-access-token',
      'client' => 'local-client',
      'uid' => 'maria@example.com',
      'expiry' => 1.hour.from_now.to_i.to_s
    }
  end
  let(:valid_cookie) { valid_cookie_payload.to_json }

  def set_session_cookie(value)
    cookies['cw_d_session_info'] = value
  end

  shared_examples 'redirects to Autonomia SSO before dashboard render' do |path, expected_return_to|
    it "redirects #{path} to Autonomia SSO" do
      with_modified_env sso_env do
        get path
      end

      redirect = URI.parse(response.location)
      params = Rack::Utils.parse_query(redirect.query)

      expect(response).to have_http_status(:found)
      expect(redirect.path).to eq('/auth/autonomia')
      expect(params['return_to']).to eq(expected_return_to)
    end
  end

  include_examples 'redirects to Autonomia SSO before dashboard render', '/', '/app'
  include_examples 'redirects to Autonomia SSO before dashboard render', '/app', '/app'
  include_examples 'redirects to Autonomia SSO before dashboard render',
                   '/app/accounts/1/dashboard?conversation=2',
                   '/app/accounts/1/dashboard?conversation=2'

  it 'renders the dashboard when the auth cookie is still valid' do
    set_session_cookie(valid_cookie)

    with_modified_env sso_env do
      get '/app/accounts/1/dashboard'
    end

    expect(response).to have_http_status(:success)
  end

  it 'redirects when the auth cookie is expired' do
    set_session_cookie(valid_cookie_payload.merge('expiry' => 1.hour.ago.to_i.to_s).to_json)

    with_modified_env sso_env do
      get '/app/accounts/1/dashboard'
    end

    expect(response).to redirect_to('/auth/autonomia?return_to=%2Fapp%2Faccounts%2F1%2Fdashboard')
  end

  it 'redirects when the auth cookie is malformed' do
    set_session_cookie('not-json')

    with_modified_env sso_env do
      get '/app/accounts/1/dashboard'
    end

    expect(response).to redirect_to('/auth/autonomia?return_to=%2Fapp%2Faccounts%2F1%2Fdashboard')
  end

  it 'does not intercept the SSO token login route' do
    with_modified_env sso_env do
      get '/app/login', params: { email: 'maria@example.com', sso_auth_token: 'sso-token' }
    end

    expect(response).to have_http_status(:success)
  end

  it 'does not intercept invitation pages' do
    with_modified_env sso_env do
      get '/accept-invitation', params: { token: 'invite-token', client_id: 'talkai' }
    end

    expect(response).to have_http_status(:success)
  end

  it 'does not intercept the SSO start route' do
    with_modified_env sso_env do
      get '/auth/autonomia'
    end

    expect(response).not_to redirect_to(%r{\A/auth/autonomia\?return_to=})
  end

  it 'does not intercept the SSO callback route' do
    with_modified_env sso_env do
      get '/auth/autonomia/callback', params: { code: 'code', state: 'state' }
    end

    expect(response).not_to redirect_to(%r{\A/auth/autonomia\?return_to=})
  end

  it 'drops an external return_to query value from the preserved destination' do
    with_modified_env sso_env do
      get '/app/accounts/1/dashboard', params: { return_to: 'https://evil.example/path' }
    end

    redirect = URI.parse(response.location)
    params = Rack::Utils.parse_query(redirect.query)

    expect(params['return_to']).to eq('/app/accounts/1/dashboard')
  end

  it 'drops a protocol-relative return_to query value from the preserved destination' do
    with_modified_env sso_env do
      get '/app/accounts/1/dashboard', params: { return_to: '//evil.example/path' }
    end

    redirect = URI.parse(response.location)
    params = Rack::Utils.parse_query(redirect.query)

    expect(params['return_to']).to eq('/app/accounts/1/dashboard')
  end

  it 'preserves the current behavior when the SSO auto redirect is disabled' do
    with_modified_env AUTONOMIA_SSO_AUTO_REDIRECT: 'false' do
      get '/app/accounts/1/dashboard'
    end

    expect(response).to have_http_status(:success)
  end
end

describe '/app/login', type: :request do
  context 'without DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      get '/app/login'
      expect(response).to have_http_status(:success)
    end
  end

  context 'with DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      with_modified_env DEFAULT_LOCALE: 'pt_BR' do
        get '/app/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include "selectedLocale: 'pt_BR'"
      end
    end
  end

  context 'with non-HTML format' do
    it 'returns not acceptable for JSON with error message' do
      get '/app/login', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.parsed_body).to eq({ 'error' => 'Please use API routes instead of dashboard routes for JSON requests' })
    end
  end

  # Routes are loaded once on app start
  # hence Rails.application.reload_routes! is used in this spec
  # ref : https://stackoverflow.com/a/63584877/939299
  context 'with CW_API_ONLY_SERVER true' do
    it 'returns 404' do
      with_modified_env CW_API_ONLY_SERVER: 'true' do
        Rails.application.reload_routes!
        get '/app/login'
        expect(response).to have_http_status(:not_found)
      end
      Rails.application.reload_routes!
    end
  end
end
