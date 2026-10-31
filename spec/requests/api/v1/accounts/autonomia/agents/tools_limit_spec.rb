require 'rails_helper'

# #1323 — a 11ª ferramenta de um agente é recusada com 422 e a mensagem do limite. Antes o limite
# fazia `throw(:abort)` num `before_create`, o `save!` levantava `RecordNotSaved` e a API respondia 500.
RSpec.describe 'Autonomia agent tools limit', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:super_admin) { create(:super_admin) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agent', agent_type: 'custom') }
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/tools" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    create(:account_user, account: account, user: super_admin, role: :administrator)
    Autonomia::Agents::Tool::MAX_PER_AGENT.times do |indice|
      Autonomia::Agents::Tool.create!(account: account, agent: agent, name: "Ferramenta #{indice}",
                                      endpoint_url: 'https://api.loja.test/estoque')
    end
  end

  it 'refuses the 11th tool with 422 and the limit message, saving nothing' do
    expect do
      post path, headers: super_admin.create_new_auth_token, as: :json,
                 params: { tool: { name: 'Mais uma', endpoint_url: 'https://api.loja.test/estoque' } }
    end.not_to change(Autonomia::Agents::Tool, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Limite de 10 ferramentas por agente atingido')
  end
end
