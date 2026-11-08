require 'rails_helper'

# #1430 (decisão do Rodrigo, 31/10): ferramenta de agente não tem limite de quantidade. Antes eram 10, e a 11ª
# respondia 500 (#1323). O guia de function calling da OpenAI (Responses API) não traz teto de funções por pedido;
# só sugere poucas por turno, para a precisão.
RSpec.describe 'Autonomia agent tools without a quantity limit', type: :request do
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
    10.times do |indice|
      Autonomia::Agents::Tool.create!(account: account, agent: agent, name: "Ferramenta #{indice}",
                                      endpoint_url: 'https://api.loja.test/estoque')
    end
  end

  it 'creates the 11th tool' do
    expect do
      post path, headers: super_admin.create_new_auth_token, as: :json,
                 params: { tool: { name: 'Mais uma', endpoint_url: 'https://api.loja.test/estoque' } }
    end.to change(Autonomia::Agents::Tool, :count).by(1)

    expect(response).to have_http_status(:created)
  end
end
