require 'rails_helper'

# Gerenciador simples (#2198, PR 1) com funções personalizadas: `meta_ads_view` vê orçamento e pausados, mas não lê as
# opções de criar (Páginas, Instagram, números e fotos), não sobe mídia, não cria anúncio e não muda orçamento (403 sem
# chamar a Meta); `meta_ads_manage` muda. Fica em spec/enterprise:
# a metade de função personalizada do permission_granted? é EE.
RSpec.describe 'Anúncios da Meta: criar e orçamento com funções (#2198)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create_account_and_user.first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:ad_id) { '120000000000216101' }
  let(:adset_id) { '120000000000021611' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:connection) { create_meta_ads_insights_connection(account) }

  before do
    travel_to Time.zone.parse('2026-10-27 12:00:00 -0300')
    account.enable_features!('meta_ads_criar')
    stub_graph('me/permissions', { data: [{ permission: 'ads_management', status: 'granted' }] })
    stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, campaign: { id: '1', name: 'Vendas' },
                        adset: { id: adset_id, name: 'Público', daily_budget: '3000', start_time: '2026-10-01T09:00:00-0300' } },
               fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)
    stub_graph("#{adset_id}/ads", { data: [{ effective_status: 'ACTIVE' }] })
    stub_graph("act_#{connection.ad_account_id}", { currency: 'BRL' })
  end

  def stub_graph(path, body, fields: nil)
    stub_request(:get, meta_graph_url(path)).with(query: fields ? { fields: fields } : hash_including({}))
                                            .to_return(status: 200, body: body.to_json, headers: json)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  it 'meta_ads_view não lê as opções de criar (Páginas, Instagram, números e fotos), sem chamar a Meta' do
    get "#{path}/create_options", headers: pessoa_com(%w[meta_ads_view]).create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(a_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))).not_to have_been_made
  end

  it 'meta_ads_view lê o orçamento, mas não sobe mídia, não cria e não muda orçamento, sem chamar a Meta' do
    viewer = pessoa_com(%w[meta_ads_view])
    headers = viewer.create_new_auth_token

    get "#{path}/ads/#{ad_id}/budget", headers: headers, as: :json
    expect(response).to have_http_status(:ok)

    post "#{path}/media", params: { file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png') }, headers: headers
    expect(response).to have_http_status(:forbidden)

    post "#{path}/ads", params: { idempotency_key: 'k', name: 'Bolo', destination: 'WHATSAPP' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    patch "#{path}/ads/#{ad_id}/budget", params: { amount: '40' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    expect(Crm::MetaAdsCreatedObject.count).to eq(0)
  end

  it 'meta_ads_view não lê os posts para impulsionar nem impulsiona (#2339), sem chamar a Meta' do
    headers = pessoa_com(%w[meta_ads_view]).create_new_auth_token

    get "#{path}/boost_posts", params: { page_id: '110' }, headers: headers
    expect(response).to have_http_status(:forbidden)

    post "#{path}/ads", params: { kind: 'post', post_source: 'instagram', post_id: '1790' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(a_request(:get, meta_graph_url('110/published_posts')).with(query: hash_including({}))).not_to have_been_made
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  # Pedido da Funções no PR 1: ligar ou pausar anúncio é mudar, não ver.
  it 'meta_ads_view não liga nem pausa anúncio (403), sem chamar a Meta' do
    account.enable_features!('meta_ads_gestao')
    headers = pessoa_com(%w[meta_ads_view]).create_new_auth_token

    post "#{path}/ads/#{ad_id}/status", params: { status: 'ACTIVE' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'meta_ads_manage muda o orçamento' do
    manager = pessoa_com(%w[meta_ads_manage])
    update = stub_request(:post, meta_graph_url(adset_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    patch "#{path}/ads/#{ad_id}/budget", params: { amount: '40' }, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(update).to have_been_made.once
  end
end
