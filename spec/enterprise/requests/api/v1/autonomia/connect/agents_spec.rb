require 'rails_helper'

RSpec.describe 'Autonom.ia Connect Agents provisioning', type: :request do
  let(:account) { create(:account, name: 'Atendimento') }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:identity_subject) { 'auth-user-123' }
  let(:verifier) { instance_double(Autonomia::Connect::JwtVerifier, verify!: { 'sub' => identity_subject }) }
  let(:headers) { { 'Authorization' => 'Bearer signed-connect-token' } }

  before do
    Autonomia::UserLink.create!(identity_user_id: identity_subject, user: user)
    allow(Autonomia::Connect::JwtVerifier).to receive(:new).and_return(verifier)
  end

  it 'lists only accounts linked to the authenticated Autonom.ia subject and marks administrator eligibility' do
    agent_account = create(:account, name: 'Somente agente')
    create(:account_user, account: agent_account, user: user, role: :agent)
    other_account = create(:account, name: 'Outra empresa')

    get '/api/v1/autonomia/connect/agents/accounts', headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['accounts']).to contain_exactly(
      include('id' => account.id, 'name' => 'Atendimento', 'eligible' => true),
      include('id' => agent_account.id, 'name' => 'Somente agente', 'eligible' => false)
    )
    expect(response.body).not_to include(other_account.name)
  end

  it 'provisions and rotates a dedicated scoped token for an administrator account' do
    post '/api/v1/autonomia/connect/agents/integration',
         params: { account_id: account.id }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    first_token = response.parsed_body.fetch('access_token')
    expect(first_token).to be_present
    expect(response.parsed_body['scopes']).to match_array(Mcp::IntegrationToken::DEFAULT_SCOPES)

    post '/api/v1/autonomia/connect/agents/integration/rotate',
         params: { account_id: account.id }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('access_token')).not_to eq(first_token)
    expect(AccessToken.find_by(token: first_token)).to be_nil
  end

  it 'denies provisioning for a non-administrator membership and never crosses accounts' do
    agent_account = create(:account)
    create(:account_user, account: agent_account, user: user, role: :agent)

    post '/api/v1/autonomia/connect/agents/integration',
         params: { account_id: agent_account.id }, headers: headers, as: :json

    expect(response).to have_http_status(:forbidden)

    post '/api/v1/autonomia/connect/agents/integration',
         params: { account_id: create(:account).id }, headers: headers, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'revokes the upstream credential synchronously' do
    integration = Mcp::IntegrationToken.create!(
      account: account,
      created_by: user,
      identity_subject: identity_subject,
      name: 'Autonom.ia Connect',
      scopes: Mcp::IntegrationToken::DEFAULT_SCOPES
    )
    raw_token = integration.access_token.token

    delete '/api/v1/autonomia/connect/agents/integration',
           params: { account_id: account.id }, headers: headers, as: :json

    expect(response).to have_http_status(:no_content)
    expect(AccessToken.find_by(token: raw_token)).to be_nil
    expect(Mcp::IntegrationToken.find_by(id: integration.id)).to be_nil
  end
end
