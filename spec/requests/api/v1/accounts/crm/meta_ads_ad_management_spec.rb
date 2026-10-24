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

  it 'pausa e grava na Auditoria da conta quem pausou, sem o token' do
    stub_meta
    Crm::MetaAdObject.create!(account: account, meta_object_id: ad_id, object_type: 'ad', name: 'Capa')
    update = stub_request(:post, meta_graph_url(ad_id)).with(body: { status: 'PAUSED' })
                                                       .to_return(status: 200, body: { success: true }.to_json, headers: json)

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'PAUSED')
    expect(update).to have_been_requested.once
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_status').last
    expect(audit).to have_attributes(user_id: admin.id)
    expect(audit.audited_changes).to eq('ad_id' => ad_id, 'ad_name' => 'Capa', 'status' => 'PAUSED')
    expect(audit.audited_changes.to_json).not_to include(MetaAdsHelpers::TEST_TOKEN)
  end

  it 'falha ao gravar a Auditoria não vira 500: a Meta já mudou, a resposta diz a situação nova e o erro vai ao rastreador' do
    stub_meta
    stub_request(:post, meta_graph_url(ad_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'PAUSED')
    expect(tracker).to have_received(:capture_exception)
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

  it 'POST em anúncio de outra conta dá 404; Meta fora do ar dá 422 meta_unavailable' do
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: [{ permission: 'ads_management', status: 'granted' }] }.to_json, headers: json)
    stub_request(:get, meta_graph_url('999')).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json, body: { id: '999', account_id: '1' }.to_json)
    post "#{path}/ads/999/status", params: { status: 'PAUSED' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'ad_not_found')

    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({})).to_return(status: 503, body: '{}', headers: json)
    allow(Rails.logger).to receive(:warn)
    get "#{path}/ads/#{ad_id}/management", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'meta_unavailable')
  end

  it 'id com parâmetros escondidos (%3F) não chega à Meta' do
    post "#{path}/ads/#{ad_id}%3Fmethod%3Ddelete/status", params: { status: 'PAUSED' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'sem conexão com conta de anúncios dá 404 not_connected' do
    Crm::MetaAdsConnection.find_by(account_id: account.id).destroy!

    get "#{path}/pages", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'not_connected')
  end
end
