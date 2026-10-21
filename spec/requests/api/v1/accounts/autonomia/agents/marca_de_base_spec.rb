require 'rails_helper'

# MARCA DE BASE (#1429): a API do agente nunca escreve `config.base`; o agente criado por ela nasce com a marca da conta
# quando a Fase 2 está ligada. O texto gravado é dado nosso: não sai em jbuilder nenhum.
RSpec.describe 'Autonomia agent base mark', type: :request do
  let(:account) { conta_da_fase2 }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:headers) { administrator.create_new_auth_token }
  let(:forjada) { { 'segmento' => 'seguros/seguradora', 'versao' => 'forjada', 'texto' => 'TEXTO FORJADO' } }
  let(:corretora) { { 'segmento' => 'seguros/corretora', 'versao' => nil, 'texto' => nil } }
  let(:gravada) { { 'segmento' => 'seguros/corretora', 'versao' => 'v1', 'texto' => 'TEXTO SECRETO DO RAMO' } }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true') { example.run }
  end

  before do
    account.update!(internal_attributes: account.internal_attributes.to_h.merge(
      Autonomia::Agents::Nicho::NICHO_KEY => 'seguros', Autonomia::Agents::Nicho::PERFIL_KEY => 'corretora'
    ))
  end

  def criar(config)
    corpo = { agent: { name: 'Manual', agent_type: 'custom', mode: 'manual', instruction: 'Atenda.', config: config } }
    post "/api/v1/accounts/#{account.id}/autonomia/agents", headers: headers, as: :json, params: corpo
  end

  it 'POST ignora a base forjada e grava a marca da conta' do
    criar('with_knowledge' => false, 'base' => forjada)

    expect(response).to have_http_status(:created)
    expect(Autonomia::Agents::Agent.find(response.parsed_body['id']).config['base']).to eq(corretora)
  end

  it 'POST sem a Fase 2 não grava marca' do
    Autonomia::Agents::Fase2.desligar!(account)
    criar('with_knowledge' => false, 'base' => forjada)

    expect(response).to have_http_status(:created)
    expect(Autonomia::Agents::Agent.find(response.parsed_body['id']).config).not_to have_key('base')
  end

  it 'PATCH com config.base forjado é ignorado e a marca salva fica' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom',
                                              config: { 'with_knowledge' => false, 'base' => corretora })

    corpo = { agent: { name: 'Ana 2', config: { 'base' => forjada } } }
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}", headers: headers, as: :json, params: corpo

    expect(response).to have_http_status(:success)
    expect(agente.reload).to have_attributes(name: 'Ana 2')
    expect(agente.config['base']).to eq(corretora)
  end

  it 'PATCH forjando só base.texto é ignorado' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom',
                                              config: { 'with_knowledge' => false, 'base' => gravada })

    corpo = { agent: { config: { 'base' => { 'texto' => 'TEXTO FORJADO' } } } }
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}", headers: headers, as: :json, params: corpo

    expect(response).to have_http_status(:success)
    expect(agente.reload.config['base']).to eq(gravada)
  end

  it 'o texto gravado não sai no agente, na lista nem nas versões' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', instruction: 'Atenda.',
                                              config: { 'with_knowledge' => false, 'base' => gravada })
    agente.record_instruction_version!(reason: 'builder_create')

    base = "/api/v1/accounts/#{account.id}/autonomia/agents"
    ["#{base}/#{agente.id}", base, "#{base}/#{agente.id}/instruction_versions"].each do |caminho|
      get caminho, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('TEXTO SECRETO DO RAMO')
    end
  end

  it 'PATCH não cria marca em agente sem marca' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', config: { 'with_knowledge' => false })

    corpo = { agent: { config: { 'base' => forjada } } }
    patch "/api/v1/accounts/#{account.id}/autonomia/agents/#{agente.id}", headers: headers, as: :json, params: corpo

    expect(response).to have_http_status(:success)
    expect(agente.reload.config).not_to have_key('base')
  end
end
