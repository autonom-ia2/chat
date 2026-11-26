require 'rails_helper'

# #3211 (Tarefa 9): a API genérica do agente não forja nem edita o que só o "Contratar" grava: a marca, a versão da base,
# as ferramentas e o material da base.
RSpec.describe 'Autonomia agente contratado: travas da API', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let!(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca, 'contratado_base_versao' => 'v-original' })
  end
  let(:agents_url) { "/api/v1/accounts/#{account.id}/autonomia/agents" }
  let(:agent_url) { "#{agents_url}/#{agente.id}" }
  let(:tools_url) { "#{agent_url}/tools" }
  let(:sources_url) { "#{agent_url}/sources" }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    enable_test_encryption!
    account.enable_features!('agente_ferramentas_delegadas')
  end

  it 'PATCH não grava nem troca a marca' do
    patch agent_url, params: { agent: { config: { contratado: { modelo: 'seguro_viagem_universal', nome_corretora: 'Forjada' } } } },
                     headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(agente.reload.config['contratado']['nome_corretora']).to eq('Corretora Exemplo')
  end

  it 'PATCH não grava a versão da base' do
    patch agent_url, params: { agent: { config: { contratado_base_versao: 'forjada' } } },
                     headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(agente.reload.config['contratado_base_versao']).to eq('v-original')
  end

  it 'POST create não nasce contratado pela API genérica' do
    post agents_url, params: { agent: { name: 'X', agent_type: 'sdr', config: { contratado: marca, contratado_base_versao: 'forjada' } } },
                     headers: admin.create_new_auth_token, as: :json

    criado = Autonomia::Agents::Agent.where.not(id: agente.id).order(:id).last
    expect(criado.contratado?).to be(false)
    expect(criado.config).not_to include('contratado_base_versao')
  end

  it 'PATCH com instruction recusa com instrucao_mantida' do
    patch agent_url, params: { agent: { instruction: 'x' } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'ferramentas: dono não cria nem apaga' do
    post tools_url, params: { tool: { name: 'x' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.ferramenta_no_contratado'))

    ferramenta = Autonomia::Agents::Tool.create!(account: account, agent: agente, name: 'Frete', endpoint_url: 'https://api.loja.test/frete')
    delete "#{tools_url}/#{ferramenta.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Agents::Tool.exists?(ferramenta.id)).to be(true)
  end

  it 'base: dono não envia, apaga nem relê material' do
    post sources_url, params: { source: { source_type: 'text', content: 'x' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.base_do_contratado'))

    fonte = agente.sources.create!(account: account, source_type: 'txt', reference: 'material.txt', kind: :knowledge)
    delete "#{sources_url}/#{fonte.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Agents::Source.exists?(fonte.id)).to be(true)

    post "#{sources_url}/#{fonte.id}/resync", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
