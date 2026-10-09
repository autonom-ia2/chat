require 'rails_helper'

RSpec.describe 'Autonomia agent voice', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def create_agent(config: {})
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'custom', config: config)
  end

  it 'writes the typed top-level voice and keeps it out of the public config contract' do
    agent = create_agent(config: { 'handoff_strategy' => 'none' })

    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          params: { agent: { voice: 'masculina' } }, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(agent.reload.config).to include('voice' => 'masculina', 'handoff_strategy' => 'none')
    expect(response.parsed_body.fetch('voice')).to eq('masculina')
    expect(response.parsed_body.fetch('config')).not_to have_key('voice')
  end

  it 'rejects invalid voice values without echoing the value' do
    agent = create_agent

    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          params: { agent: { voice: 'robot' } }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'invalid_enum', 'key' => 'voice')
    expect(response.body).not_to include('robot')
    expect(agent.reload.config).not_to have_key('voice')
  end

  it 'rejects a non-string voice value' do
    agent = create_agent

    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}",
          params: { agent: { voice: true } }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'invalid_enum', 'key' => 'voice')
  end

  it 'starts quote agents with the feminine voice' do
    agent = Autonomia::Insurance::QuoteAgent::Builder.new(
      account: account, nome_agente: 'Lia', nome_corretora: 'Sena'
    ).call

    expect(agent.reload.config['voice']).to eq('feminina')
  end

  it 'accepts the typed voice on agent creation' do
    post "/api/v1/accounts/#{account.id}/autonomia/agents",
         params: { agent: { name: 'Novo', agent_type: 'custom', voice: 'masculina' } },
         headers: headers, as: :json

    expect(response).to have_http_status(:created)
    created = Autonomia::Agents::Agent.find(response.parsed_body.fetch('id'))
    expect(created.config['voice']).to eq('masculina')
    expect(response.parsed_body.fetch('voice')).to eq('masculina')
  end
end
