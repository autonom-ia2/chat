require 'rails_helper'

# #284 (Entrega 2a) — público-alvo e horário de atuação vão e voltam pela API do agente.
RSpec.describe 'Autonomia agent engagement settings', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', instruction: 'Atenda.',
                                     config: { 'handoff_strategy' => 'none' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}" }
  let(:audience) do
    { 'operator' => 'and',
      'conditions' => [
        { 'attribute_key' => 'country_code', 'filter_operator' => 'equal_to', 'values' => ['BR'] },
        { 'operator' => 'or',
          'conditions' => [{ 'attribute_key' => 'labels', 'filter_operator' => 'equal_to', 'values' => %w[vip] },
                           { 'attribute_key' => 'email', 'filter_operator' => 'contains', 'values' => ['@acme.com'] }] }
      ] }
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'saves and exposes the audience tree and the response window' do
    patch url, params: { agent: { config: { audience: audience, response_window: 'business_hours' } } },
               headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('config', 'audience')).to eq(audience)
    expect(response.parsed_body.dig('config', 'response_window')).to eq('business_hours')
    expect(agent.reload.config).to include('audience' => audience, 'response_window' => 'business_hours',
                                           'handoff_strategy' => 'none')
  end

  it 'clears the audience with null (everyone)' do
    agent.update!(config: agent.config.merge('audience' => audience))

    patch url, params: { agent: { config: { audience: nil } } }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(agent.reload.config['audience']).to be_nil
  end

  it 'rejects an invalid audience tree and an unknown response window' do
    patch url, params: { agent: { config: { audience: { 'attribute_key' => 'name', 'filter_operator' => 'contains', 'values' => ['x'] } } } },
               headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch url, params: { agent: { config: { response_window: 'lunch' } } }, headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
