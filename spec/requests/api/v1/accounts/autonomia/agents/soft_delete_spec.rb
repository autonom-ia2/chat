require 'rails_helper'

RSpec.describe 'Autonomia agent logical deletion', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agent', agent_type: 'custom') }
  let(:headers) { administrator.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'keeps the DELETE response while preserving the record and author' do
    delete path, headers: headers, as: :json

    expect(response).to have_http_status(:no_content)
    expect(agent.reload.deleted_by_id).to eq(administrator.id)
    expect(agent).to be_deleted
  end

  it 'does not list or expose an archived agent' do
    Autonomia::Agents::SoftDelete.new(agent: agent, actor: administrator).perform

    get "/api/v1/accounts/#{account.id}/autonomia/agents", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.to_json).not_to include('"name":"Agent"')

    get path, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'refuses updates and tests after deletion' do
    Autonomia::Agents::SoftDelete.new(agent: agent, actor: administrator).perform

    patch path, headers: headers, params: { agent: { enabled: true, status: 'active' } }, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{path}/test", headers: headers, params: { query: 'Hello' }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'does not allow deleting another account agent' do
    other = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    foreign_agent = Autonomia::Agents::Agent.create!(account: other, name: 'Foreign', agent_type: 'custom')

    delete "/api/v1/accounts/#{account.id}/autonomia/agents/#{foreign_agent.id}", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(foreign_agent.reload).not_to be_deleted
  end
end
