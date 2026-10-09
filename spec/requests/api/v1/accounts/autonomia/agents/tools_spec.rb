require 'rails_helper'

RSpec.describe 'Autonomia agent tools', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:super_admin) { create(:super_admin) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Agente de ferramentas', agent_type: 'custom', instruction: 'Atenda.'
    )
  end
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account,
      agent: agent,
      name: 'Consulta privada',
      slug: 'consulta_privada',
      endpoint_url: 'https://example.test/lookup',
      headers_config: [{ key: 'Authorization', value: 'token-original', secret: true }]
    )
  end

  before do
    create(:account_user, account: account, user: super_admin, role: :administrator)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def update_tool(attributes)
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/tools/#{tool.id}",
          params: { tool: attributes }, headers: super_admin.create_new_auth_token, as: :json
  end

  it 'preserves an existing secret omitted by the masked edit form' do
    update_tool(
      description: 'Descrição atualizada',
      headers_config: [{ key: 'Authorization', secret: true }]
    )

    expect(response).to have_http_status(:success)
    expect(tool.reload.headers_config).to include(
      include('key' => 'Authorization', 'value' => 'token-original', 'secret' => true)
    )
  end

  it 'preserves an existing secret when secret false arrives without a value' do
    update_tool(headers_config: [{ key: 'Authorization', secret: false }])

    expect(response).to have_http_status(:success)
    expect(tool.reload.headers_config).to include(
      include('key' => 'Authorization', 'value' => 'token-original', 'secret' => true)
    )
  end

  it 'preserves an existing secret when the masked placeholder arrives with secret false' do
    update_tool(
      headers_config: [{ key: 'Authorization', value: Autonomia::Agents::Tool.masked_header_value, secret: false }]
    )

    expect(response).to have_http_status(:success)
    header = tool.reload.headers_config.find { |item| item['key'] == 'Authorization' }
    expect(header).to include('secret' => true, 'value' => 'token-original')
    expect(header['value']).not_to eq(Autonomia::Agents::Tool.masked_header_value)
  end

  it 'clears the placeholder for a new non-secret header' do
    update_tool(
      headers_config: [{ key: 'X-New', value: Autonomia::Agents::Tool.masked_header_value, secret: false }]
    )

    expect(response).to have_http_status(:success)
    header = tool.reload.headers_config.find { |item| item['key'] == 'X-New' }
    expect(header).to include('secret' => false, 'value' => '')
    expect(header['value']).not_to eq(Autonomia::Agents::Tool.masked_header_value)
  end
end
