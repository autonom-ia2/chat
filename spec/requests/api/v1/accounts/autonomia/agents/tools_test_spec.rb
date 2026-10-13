require 'rails_helper'

# #1425 — o teste da tela mostra EXATAMENTE o texto que o agente lê no atendimento: o mesmo corte
# (`Bound#cabendo`, 8.000 caracteres com o aviso) e o mesmo tratamento de erro (`Bound`/`Recusa`).
RSpec.describe 'Autonomia agent tool test', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:super_admin) { create(:super_admin) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Agent', agent_type: 'custom') }
  let(:endpoint) { 'https://api.loja.test/estoque' }
  let(:tool) do
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Estoque', slug: 'estoque', http_method: 'GET',
      endpoint_url: endpoint, headers_config: [{ key: 'x-api-key', value: 'chave-da-loja-987', secret: true }],
      param_schema: []
    )
  end
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/tools/#{tool.id}/test" }
  let(:bound) { Autonomia::Agents::Tools::Bound.new(agent: agent, record: tool) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before do
    create(:account_user, account: account, user: super_admin, role: :administrator)
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.loja.test').and_return(['93.184.216.34'])
  end

  def testar
    post path, headers: super_admin.create_new_auth_token, params: { params: {} }, as: :json
  end

  it 'shows the same cut text the agent reads, with the cut warning' do
    resposta = "texto #{'x' * 20_000}"
    stub_request(:get, endpoint).to_return(status: 200, body: resposta, headers: { 'Content-Type' => 'text/plain' })

    testar

    expect(response).to have_http_status(:ok)
    esperado = bound.cabendo(resposta)
    expect(response.parsed_body['body']).to eq(esperado)
    expect(response.parsed_body['body'].length).to eq(Autonomia::Agents::Tools::Bound::MAX_OUTPUT_CHARS)
    expect(response.parsed_body['cortada']).to be(true)
  end

  it 'shows a short answer whole, not cut' do
    stub_request(:get, endpoint).to_return(status: 200, body: '{"a":1}', headers: { 'Content-Type' => 'application/json' })

    testar

    expect(response.parsed_body).to include('status' => 'ok', 'body' => '{"a":1}', 'cortada' => false)
  end

  it 'on a 4xx, shows what the agent receives: status and a cleaned piece of the body' do
    stub_request(:get, endpoint).to_return(status: [400, 'Bad Request'], body: '{"erro":"falta o cep","eco":"chave-da-loja-987"}')

    testar

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('tool_http_error: 400 Bad Request')
    agente = JSON.parse(response.parsed_body['agente_recebe'])
    expect(agente['error']).to eq('tool_http_error: 400')
    expect(agente['resposta']).to include('falta o cep')
    expect(response.body).not_to include('chave-da-loja-987')
  end
end
