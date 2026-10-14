require 'rails_helper'

# Tema 14 (#1434): a API do vínculo do ajudante. Atrás da chave da Fase 2; só o escritor único grava.
RSpec.describe 'Ajuda do agente (tema 14)', type: :request do
  let(:conta) { conta_da_fase2 }
  let(:administrator) { create(:user, account: conta, role: :administrator) }
  let(:agent_user) { create(:user, account: conta, role: :agent) }
  let(:joana) { criar_principal(conta) }
  let(:clara) { criar_principal(conta, nome: 'Clara') }
  let(:ajudante) { criar_ajudante(conta) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true', CRM_COPILOT_ENABLED: 'true') { example.run } }

  def caminho(agente = ajudante)
    "/api/v1/accounts/#{conta.id}/autonomia/agents/#{agente.id}/ajuda"
  end

  def gravar(principal_ids:, quando: 'Dúvida do produto Auto', usuario: administrator)
    put caminho, params: { principal_ids: principal_ids, quando: quando }, headers: usuario.create_new_auth_token, as: :json
  end

  it 'grava quem o ajudante ajuda e o "quando chamar", e devolve o estado' do
    gravar(principal_ids: [joana.id, clara.id])

    expect(response).to have_http_status(:ok)
    corpo = response.parsed_body
    expect(corpo['quando']).to eq('Dúvida do produto Auto')
    expect(corpo['principais'].pluck('id')).to contain_exactly(joana.id, clara.id)
  end

  it 'lê o mesmo estado no GET' do
    gravar(principal_ids: [joana.id])

    get caminho, headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body['principais'].pluck('name')).to eq(['Joana'])
  end

  it 'recusa principal de outra conta com 422' do
    de_fora = criar_principal(conta_da_fase2)

    gravar(principal_ids: [de_fora.id])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Autonomia::Agents::Specialist.where(delegate_agent_id: ajudante.id)).to be_empty
  end

  it 'entrada fora do formato dá 422, nunca 500' do
    base = { quando: 'Dúvida do Auto' }
    [
      { principal_ids: { 'a' => joana.id } },
      { principal_ids: ['abc'] },
      { principal_ids: [{ 'id' => joana.id }] },
      { principal_ids: [joana.id], quando: { 'texto' => 'x' } }
    ].each do |corpo|
      put caminho, params: base.merge(corpo), headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity), "corpo #{corpo.inspect} -> #{response.status}"
    end
    expect(Autonomia::Agents::Specialist.where(delegate_agent_id: ajudante.id)).to be_empty
  end

  it 'recusa lista vazia com 422' do
    gravar(principal_ids: [])

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'com a Fase 2 desligada, a rota não existe para a conta (404)' do
    conta.update!(internal_attributes: conta.internal_attributes.merge('autonomia_agents_fase2' => false))

    gravar(principal_ids: [joana.id])

    expect(response).to have_http_status(:not_found)
  end

  it 'escrita é só de quem gerencia agentes' do
    gravar(principal_ids: [joana.id], usuario: agent_user)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'a página do agente diz quem ele ajuda' do
    gravar(principal_ids: [joana.id])

    get "/api/v1/accounts/#{conta.id}/autonomia/agents/#{ajudante.id}", headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body['ajuda']).to eq([{ 'id' => joana.id, 'name' => 'Joana' }])
    expect(response.parsed_body['tem_onde_trabalhar']).to be(true)
  end

  it 'o ajudante vinculado sai do seletor do Copiloto da conversa' do
    gravar(principal_ids: [joana.id])
    conversa = create(:conversation, account: conta)

    get "/api/v1/accounts/#{conta.id}/autonomia/conversations/#{conversa.display_id}/copilot/agents",
        headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body['agents'].pluck('id')).not_to include(ajudante.id)
  end
end
