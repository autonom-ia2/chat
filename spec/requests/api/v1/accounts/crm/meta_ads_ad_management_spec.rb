require 'rails_helper'

# Gestão mínima do anúncio (#2161): sem a flag 404 sem chamar a Meta; ver pede meta_ads_view, mudar pede
# meta_ads_manage (agente comum: 403); sem conexão 404; a mudança fica no log com quem e o quê, sem o token.
RSpec.describe 'CRM meta_ads_connection ad management (#2161)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:ad_id) { '120254710382770416' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('meta_ads_gestao')
    create_meta_ads_insights_connection(account)
  end

  def stub_meta(status: 'ACTIVE')
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: [{ permission: 'ads_management', status: 'granted' }] }.to_json, headers: json)
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: '2196424464528988', status: status,
                                                                effective_status: status, creative: { id: '9' } }.to_json)
  end

  it 'sem a flag responde 404 e não chama a Meta' do
    account.disable_features!('meta_ads_gestao')

    get "#{path}/ads/#{ad_id}/management", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'mostra a situação do anúncio ao administrador, que pode mudar' do
    stub_meta

    get "#{path}/ads/#{ad_id}/management", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['management']).to include('status' => 'ACTIVE', 'can_change' => true, 'post' => nil)
  end

  it 'pausa e registra no log quem pausou, sem o token' do
    stub_meta
    update = stub_request(:post, meta_graph_url(ad_id)).with(body: { status: 'PAUSED' })
                                                       .to_return(status: 200, body: { success: true }.to_json, headers: json)
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message.to_s }

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'PAUSED')
    expect(update).to have_been_requested.once
    line = logged.find { |message| message.include?('[MetaAdsManagement]') }
    expect(line).to include("account=#{account.id}", "user=#{admin.id}", "ad=#{ad_id}", 'status=PAUSED')
    expect(line).not_to include(MetaAdsHelpers::TEST_TOKEN)
  end

  it 'agente comum não vê nem muda' do
    get "#{path}/ads/#{ad_id}/management", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'situação inválida dá 422 e anúncio de outra conta dá 404' do
    stub_meta
    post "#{path}/ads/#{ad_id}/status", params: { status: 'DELETED' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_status')

    stub_request(:get, meta_graph_url('999')).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json, body: { id: '999', account_id: '1' }.to_json)
    get "#{path}/ads/999/management", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'sem conexão com conta de anúncios dá 404 not_connected' do
    Crm::MetaAdsConnection.find_by(account_id: account.id).destroy!

    get "#{path}/pages", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'not_connected')
  end
end
