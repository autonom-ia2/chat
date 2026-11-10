require 'rails_helper'

# #2858 F3 — o cartão "pode ganhar" pela API: a mesma porta da vitrine (administrador ou a chave "Ferramentas dos
# agentes"), mais a flag do Construtor. A página recebe a sugestão que já existe e nunca espera o modelo: a nova sai em
# segundo plano. Uma conta não lê nem dispensa a sugestão de outra.
RSpec.describe 'Sugestões de ferramentas prontas', type: :request do
  include FerramentasProntasHelper

  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr', instruction: 'Cota seguro auto.') }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/ferramentas_prontas" }
  let(:admin) { create(:user, :administrator, account: account) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before do
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE, Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
  end

  after { Redis::Alfred.delete("#{Autonomia::FerramentasProntas::SugestaoJob::TRAVA}:#{agent.id}") }

  def sugerir(chaves)
    Autonomia::FerramentasProntas::SugestaoParaAgente.gravar(
      agent, 'prontas_sugestao' => { 'chaves' => chaves, 'assinatura' => Autonomia::FerramentasProntas::SugestaoParaAgente.assinatura(account) }
    )
  end

  it 'answers the stored suggestion right away and asks for a new one in the background when missing' do
    get "#{base}/sugestoes", params: { agent_id: agent.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('ferramentas' => [])
    expect(Autonomia::FerramentasProntas::SugestaoJob).to have_been_enqueued.with(agent.id)
  end

  it 'does not ask again while the stored one is current' do
    sugerir(%w[fipe])

    get "#{base}/sugestoes", params: { agent_id: agent.id }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('ferramentas' => %w[fipe])
    expect(Autonomia::FerramentasProntas::SugestaoJob).not_to have_been_enqueued
  end

  it '"Not now" removes that suggestion for that agent' do
    sugerir(%w[fipe cpf])

    post "#{base}/dispensar", params: { agent_id: agent.id, fonte: 'fipe' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:no_content)

    get "#{base}/sugestoes", params: { agent_id: agent.id }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('ferramentas' => %w[cpf])
  end

  it 'refuses an unknown source' do
    post "#{base}/dispensar", params: { agent_id: agent.id, fonte: 'inventada' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'without the Construtor flag: 404 with the reason' do
    account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)

    get "#{base}/sugestoes", params: { agent_id: agent.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('motivo' => 'desligada')
  end

  it 'an agent without the tools key gets 401' do
    pessoa = create(:user, account: account, role: :agent)

    get "#{base}/sugestoes", params: { agent_id: agent.id }, headers: pessoa.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'one account never reads nor dismisses the suggestion of another' do
    sugerir(%w[fipe])
    outra = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    ligar_consultas(outra)
    outra.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE, Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
    admin_da_outra = create(:user, :administrator, account: outra)
    da_outra = "/api/v1/accounts/#{outra.id}/autonomia/ferramentas_prontas"

    get "#{da_outra}/sugestoes", params: { agent_id: agent.id }, headers: admin_da_outra.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{da_outra}/dispensar", params: { agent_id: agent.id, fonte: 'fipe' }, headers: admin_da_outra.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(agent.reload.config).not_to have_key('prontas_dispensadas')
  end
end
