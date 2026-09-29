require 'rails_helper'

RSpec.describe 'Interactive AI integration-token authorization', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last,
                              title: 'Teste', owner: token.account_user.user)
  end
  let(:token) { Crm::IntegrationToken.create!(account: account, created_by: admin, name: 'Teste', scopes: %w[crm_view crm_manage_ai]) }
  let(:headers) { { api_access_token: token.access_token.token } }
  let(:service) { instance_double(Crm::Ai::Evaluator, perform: Crm::Ai::Evaluator::Result.new(status: :skipped)) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before { allow(Crm::Ai::Evaluator).to receive(:new).and_return(service) }

  it 'lets the same scoped token poll its own result, without opening other endpoints' do
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/evaluate_ai", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('done')

    get "/api/v1/accounts/#{account.id}/conversations", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not execute queued work or expose the result after token revocation' do
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/evaluate_ai", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    token.update!(status: :revoked)
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    expect(service).not_to have_received(:perform)
    get request['poll_url'], headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
