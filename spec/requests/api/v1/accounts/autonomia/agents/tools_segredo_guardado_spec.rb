require 'rails_helper'

# #1430: a tela recebe o segredo mascarado e o devolve assim quando não mudou. O valor guardado fica, com
# `secret` em qualquer forma que o modelo entende como ligado; sem isso a máscara viraria o token.
RSpec.describe 'Autonomia agent tools keep the stored secret', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:super_admin) { create(:super_admin) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agent', agent_type: 'custom') }
  let(:tool) do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Estoque', endpoint_url: 'https://api.loja.test/estoque',
                                    headers_config: [{ key: 'Authorization', value: 'token-guardado', secret: true }])
  end
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/tools/#{tool.id}" }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { create(:account_user, account: account, user: super_admin, role: :administrator) }

  [true, 'true', '1'].each do |ligado|
    it "keeps the stored value when the masked value comes back with secret #{ligado.inspect}" do
      cabecalho = { key: 'Authorization', value: Autonomia::Agents::Tool.masked_header_value, secret: ligado }
      patch path, headers: super_admin.create_new_auth_token, as: :json, params: { tool: { headers_config: [cabecalho] } }

      expect(response).to have_http_status(:ok)
      expect(tool.reload.headers_config.first['value']).to eq('token-guardado')
    end
  end

  it 'saves a new value typed over the mask' do
    cabecalho = { key: 'Authorization', value: 'token-novo', secret: true }
    patch path, headers: super_admin.create_new_auth_token, as: :json, params: { tool: { headers_config: [cabecalho] } }

    expect(tool.reload.headers_config.first['value']).to eq('token-novo')
  end
end
