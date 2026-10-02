require 'rails_helper'

RSpec.describe 'CRM contact creation permissions (M02)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_membership) { create_crm_agent(account: account) }
  let(:agent) { agent_and_membership.first }
  let(:membership) { agent_and_membership.last }
  let(:role) { create(:custom_role, account: account, permissions: ['crm_view']) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, owner: agent, title: 'Existing')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/contact" }
  let(:payload) { { contact: { name: 'Authorized registration' } } }
  let(:headers) { auth_headers(agent).merge('Idempotency-Key' => SecureRandom.uuid) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  it 'does not let a CRM viewer create a contact on a visible card' do
    membership.update!(custom_role: role)
    card
    expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'checks current permissions before replaying a previously authorized response' do
    role.update!(permissions: %w[crm_view crm_manage_cards contact_manage])
    membership.update!(custom_role: role)
    post path, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    role.update!(permissions: ['crm_view'])

    post path, params: payload, headers: headers, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('Authorized registration')
    expect(response.headers['Idempotency-Replayed']).to be_nil
  end

  it 'keeps CRM integration tokens denied even when their CRM scope is admin' do
    token = Crm::IntegrationToken.create!(account: account, name: 'Local scope test', scopes: ['crm_admin'], created_by: admin)
    card
    expect do
      post path, params: payload, headers: { 'api_access_token' => token.access_token.token, 'Idempotency-Key' => SecureRandom.uuid }, as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('This token is only authorized for CRM endpoints')
  end

  it 'scopes card IDs to the selected account even for a user who administers both accounts' do
    card
    other = create(:account)
    create(:account_user, account: other, user: admin, role: :administrator)
    foreign_path = "/api/v1/accounts/#{other.id}/crm/cards/#{card.id}/contact"
    expect do
      post foreign_path, params: payload, headers: auth_headers(admin).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:not_found)
    expect(card.reload.contact_id).to be_nil
  end
end
