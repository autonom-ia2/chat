require 'rails_helper'

# Gerenciador simples (#2198, PR 1): sem a flag meta_ads_criar 404 sem chamar a Meta; ver orçamento e pausados pede
# meta_ads_view; opções de criar, criar, subir mídia e mudar orçamento pedem meta_ads_manage (agente comum: 403). Criar e
# mudar o orçamento ficam na Auditoria da conta com quem fez, sem o token.
RSpec.describe 'CRM meta_ads_connection creation (#2198)', type: :request do
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
  let(:ad_id) { '120000000000216101' }
  let(:adset_id) { '120000000000021611' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:connection) { create_meta_ads_insights_connection(account) }

  before do
    travel_to Time.zone.parse('2026-10-27 12:00:00 -0300')
    account.enable_features!('meta_ads_criar', 'meta_ads_gestao')
  end

  def stub_graph(path, body, fields: nil, verb: :get)
    stub = stub_request(verb, meta_graph_url(path))
    stub = stub.with(query: fields ? { fields: fields } : hash_including({})) if verb == :get
    stub.to_return(status: 200, body: body.to_json, headers: json)
  end

  def stub_permissions
    stub_graph('me/permissions', { data: [{ permission: 'ads_management', status: 'granted' }] })
  end

  def stub_budget
    stub_permissions
    stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, campaign: { id: '1', name: 'Vendas' },
                        adset: { id: adset_id, name: 'Público', daily_budget: '3000', start_time: '2026-10-01T09:00:00-0300' } },
               fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)
    stub_graph("#{adset_id}/ads", { data: [{ effective_status: 'ACTIVE' }] })
    stub_graph("act_#{connection.ad_account_id}", { currency: 'BRL' })
  end

  it 'sem a flag responde 404 e não chama a Meta' do
    account.disable_features!('meta_ads_criar')

    get "#{path}/create_options", headers: admin.create_new_auth_token, as: :json
    post "#{path}/ads", params: { idempotency_key: 'k' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'agente comum não lê opções nem cria (403)' do
    get "#{path}/create_options", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{path}/ads", params: { idempotency_key: 'k' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'lê o orçamento do anúncio' do
    stub_budget

    get "#{path}/ads/#{ad_id}/budget", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['budget']).to include('level' => 'adset', 'amount' => 30.0, 'active_ads_count' => 1)
  end

  it 'muda o orçamento e grava na Auditoria o antes e o depois, sem o token' do
    stub_budget
    stub_request(:post, meta_graph_url(adset_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    patch "#{path}/ads/#{ad_id}/budget", params: { amount: '40', end_time: nil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_budget_change').last
    expect(audit.user).to eq(admin)
    expect(audit.audited_changes).to include('ad_id' => ad_id, 'amount' => [30.0, 40.0])
    expect(audit.audited_changes.to_json).not_to include(MetaAdsHelpers::TEST_TOKEN)
  end

  it 'valor fora do limite: 422 invalid_amount' do
    stub_budget

    patch "#{path}/ads/#{ad_id}/budget", params: { amount: '1000' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_amount')
  end

  it 'falha ao criar devolve o código e se nada foi criado' do
    params = { idempotency_key: SecureRandom.uuid, name: 'Bolo', destination: 'MESSENGER' }

    post "#{path}/ads", params: params, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_destination', 'nothing_created' => true)
  end

  it 'a mesma chave de novo não grava outro "anúncio criado" na Auditoria' do
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: 'k1', status: 'created', name: 'Bolo', ad_id: ad_id)
    create(:channel_whatsapp, account: account, phone_number: '+5511900002161', validate_provider_config: false, sync_templates: false)
    params = { idempotency_key: 'k1', name: 'Bolo', destination: 'WHATSAPP', page_id: '110', whatsapp_number: '+5511900002161',
               media: { kind: 'image', hash: 'abc' }, text: 'Bolo', placement: 'AUTO', region: 'BR', age_min: 18, age_max: 65,
               daily_amount: '20', start_date: '2026-10-27' }

    post "#{path}/ads", params: params, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ad_id']).to eq(ad_id)
    expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_created')).to be_empty
  end

  it 'anúncio de outra conta de anúncios: 404 no orçamento' do
    stub_permissions
    stub_graph(ad_id, { id: ad_id, account_id: '999', adset: { id: adset_id, daily_budget: '3000' } },
               fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)

    get "#{path}/ads/#{ad_id}/budget", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'ad_not_found')
  end

  it 'pausados não trazem linha de outra conta da plataforma nem da conta de anúncios anterior' do
    other = create(:account)
    Crm::MetaAdsCreatedObject.create!(account: other, idempotency_key: 'k9', status: 'created', name: 'Outra', ad_id: '555',
                                      ad_account_id: connection.ad_account_id)
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: 'k8', status: 'created', name: 'Antiga', ad_id: '556',
                                      ad_account_id: '111')

    get "#{path}/paused_ads", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ads']).to eq([])
    expect(a_request(:get, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'lista os pausados criados aqui' do
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: 'k1', status: 'created', name: 'Bolo', ad_id: ad_id,
                                      ad_account_id: connection.ad_account_id, budget: { 'kind' => 'daily', 'amount' => 20.0 })
    stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: connection.ad_account_id, status: 'PAUSED',
                                                                effective_status: 'PAUSED' }.to_json)

    get "#{path}/paused_ads", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ads'].pluck('ad_id')).to eq([ad_id])
  end

  describe 'ativar o anúncio criado aqui (ponto 6)' do
    let!(:record) do
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: 'k1', status: 'created', name: 'Bolo', ad_id: ad_id,
                                        campaign_id: '1', adset_id: adset_id)
    end

    def stub_activation(campaign: 'ACTIVE', adset: 'ACTIVE')
      stub_permissions
      stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, status: 'PAUSED', effective_status: 'PAUSED' },
                 fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS)
      stub_graph(ad_id, { success: true }, verb: :post)
      stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, adset: { id: adset_id, effective_status: adset },
                          campaign: { id: '1', effective_status: campaign } }, fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)
    end

    it 'com campanha e grupo no ar: marca como ativado e não avisa nada' do
      stub_activation

      post "#{path}/ads/#{ad_id}/status", params: { status: 'ACTIVE' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('status' => 'ACTIVE', 'held_by' => nil)
      expect(record.reload.activated_at).to be_present
    end

    it 'campanha pausada no Gerenciador: avisa em vez de dizer que começou' do
      stub_activation(campaign: 'PAUSED')

      post "#{path}/ads/#{ad_id}/status", params: { status: 'ACTIVE' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('status' => 'ACTIVE', 'held_by' => 'campaign')
    end
  end
end
