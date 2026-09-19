require 'rails_helper'

RSpec.describe 'Autonomia Insurance Connection API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/insurance/connection" }
  let(:credentials) { { connection: { username: 'corretora@exemplo.com.br', password: 'segredo' } } }

  def enable_feature!(enabled: true)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INSURANCE_QUOTING_ENABLED', false).and_return(enabled ? 'true' : 'false')
    Autonomia::Insurance::Config.enable_for!(account) if enabled
  end

  before { enable_test_encryption! }

  describe 'gate e permissão' do
    it 'returns 404 when the feature is off for the account' do
      enable_feature!(enabled: false)
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 for a plain agent' do
      enable_feature!
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /connection' do
    it 'returns not_configured when nothing was saved' do
      enable_feature!
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to include('status' => 'not_configured', 'provider' => 'agger')
    end
  end

  describe 'POST /connection' do
    it 'stores credentials, authenticates and never echoes the password' do
      enable_feature!
      post base, params: credentials, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload['status']).to eq('discovering')
      expect(payload['username_hint']).to eq('co*******@exemplo.com.br')
      expect(payload['last_authenticated_at']).to be_present
      expect(response.body).not_to include('segredo')
      expect(response.body).not_to include('corretora@exemplo.com.br')
    end

    # #469: a descoberta passava de 15 s dentro da requisição e o Rack::Timeout devolvia 500.
    it 'does not discover capabilities inline: it enqueues the ScanJob instead' do
      enable_feature!
      connector = Autonomia::Insurance::Connector::Mock.new
      allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
      expect(connector).not_to receive(:capabilities)

      expect do
        post base, params: credentials, headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Autonomia::Insurance::Connections::ScanJob)

      connection = Autonomia::Insurance::Connection.find_by(account: account)
      expect(connection.status).to eq('discovering')
      expect(connection.capabilities).to be_blank
    end

    it 'settles to ready with capabilities once the ScanJob runs' do
      enable_feature!
      perform_enqueued_jobs(only: Autonomia::Insurance::Connections::ScanJob) do
        post base, params: credentials, headers: admin.create_new_auth_token, as: :json
      end

      get base, headers: admin.create_new_auth_token, as: :json
      payload = response.parsed_body['payload']
      expect(payload['status']).to eq('ready')
      expect(payload['capabilities']['products'].map { |p| p['product'] }).to include('auto')
    end

    it 'maps an invalid password to auth_required instead of raising, without enqueuing discovery' do
      enable_feature!
      expect do
        post base, params: { connection: { username: 'x@y.com', password: 'invalid' } },
                   headers: admin.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Autonomia::Insurance::Connections::ScanJob)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to include('status' => 'auth_required')
      expect(response.parsed_body['payload']['last_error']).to start_with('auth_required')
    end

    it 'is tenant-scoped: another account does not see the connection' do
      enable_feature!
      post base, params: credentials, headers: admin.create_new_auth_token, as: :json

      other = create(:account)
      other_admin = create(:user, account: other, role: :administrator)
      Autonomia::Insurance::Config.enable_for!(other)
      get "/api/v1/accounts/#{other.id}/autonomia/insurance/connection",
          headers: other_admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']['status']).to eq('not_configured')
    end
  end

  describe 'POST /connection/scan and /reconnect' do
    it 'refuses when nothing is configured' do
      enable_feature!
      post "#{base}/scan", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'refreshes capabilities for a configured connection' do
      enable_feature!
      post base, params: credentials, headers: admin.create_new_auth_token, as: :json
      perform_enqueued_jobs(only: Autonomia::Insurance::Connections::ScanJob) do
        post "#{base}/scan", headers: admin.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:success)
      get base, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload']['last_capability_scan_at']).to be_present
    end
  end

  describe 'DELETE /connection' do
    it 'removes the stored connection' do
      enable_feature!
      post base, params: credentials, headers: admin.create_new_auth_token, as: :json
      delete base, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Autonomia::Insurance::Connection.where(account: account)).to be_empty
    end
  end
end
