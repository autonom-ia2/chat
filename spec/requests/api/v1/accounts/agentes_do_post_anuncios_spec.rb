require 'rails_helper'

# #2479: os anúncios do "Qual post?" ao criar o cuidado dos comentários em Agentes. São os da lista de Anúncios dos
# últimos 30 dias (Panel::Report), só do banco: nenhuma chamada à Meta. As guardas são as de ver o cuidado do anúncio.
RSpec.describe 'Agentes: os anúncios do "Qual post?"', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:url) { "/api/v1/accounts/#{account.id}/agentes_do_post/anuncios" }
  let!(:connection) { create_meta_ads_insights_connection(account) }
  let(:agora) { Time.zone.parse('2026-11-04T10:00:00-03:00') }

  def gasto(ad_id, date, valor, **extra)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: date, currency: 'BRL',
                                    spend: valor, attribution_window: '7d_click', fetched_at: agora, **extra)
  end

  def nome(ad_id, texto, thumbnail_url: nil)
    Crm::MetaAdObject.create!(account: account, meta_object_id: ad_id, object_type: 'ad', name: texto, thumbnail_url: thumbnail_url,
                              fetched_at: agora)
  end

  def pedir(user = admin)
    travel_to(agora) { get url, headers: user.create_new_auth_token, as: :json }
  end

  before do
    account.enable_features!('meta_ads_comentarios_ia', 'meta_ads_gestao', 'meta_ads_comentarios_instagram',
                             'meta_ads_comentarios_facebook')
    stub_request(:any, /graph\.facebook\.com/).to_raise('a lista não lê a Meta')
  end

  it 'os anúncios dos últimos 30 dias, na ordem de Anúncios (primeiro os que trazem conversa), com nome, foto e estado' do
    nome('1201', 'Seguro viagem', thumbnail_url: 'https://cdn.exemplo/1201.jpg')
    nome('1202', 'Seguro auto')
    Crm::MetaAdObject.create!(account: account, meta_object_id: 'conjunto-site', object_type: 'adset', destination_type: 'WEBSITE',
                              fetched_at: agora)
    gasto('1201', Date.new(2026, 11, 3), 80, conversations_started: 2)
    gasto('1202', Date.new(2026, 11, 2), 30)
    gasto('1203', Date.new(2026, 11, 1), 10, adset_id: 'conjunto-site') # leva ao site: entre os outros
    gasto('1299', Date.new(2026, 9, 1), 500) # fora dos 30 dias
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '1202', network: 'both', status: 'paused')
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1203', network: 'instagram')
    create(:crm_meta_ads_comment_care, account: create(:account), target_kind: 'ad', target_id: '1201', network: 'both')

    pedir

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['anuncios']).to eq([
                                                     { 'id' => '1201', 'name' => 'Seguro viagem', 'image_url' => 'https://cdn.exemplo/1201.jpg',
                                                       'care' => nil },
                                                     { 'id' => '1202', 'name' => 'Seguro auto', 'image_url' => nil, 'care' => 'paused' },
                                                     { 'id' => '1203', 'name' => nil, 'image_url' => nil, 'care' => nil }
                                                   ])
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'sem o CRM na instalação: 404' do
    with_modified_env CRM_KANBAN_ENABLED: 'false' do
      pedir
    end

    expect(response).to have_http_status(:not_found)
  end

  it 'não pede a leitura de hoje à Meta (como faz o painel de Anúncios)' do
    expect(Crm::MetaAds::Insights::Refresh).not_to receive(:request!)
    expect(Crm::MetaAds::InsightsSyncJob).not_to receive(:perform_later)

    pedir

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['anuncios']).to eq([])
  end

  it 'sem conexão ativa com conta de anúncios: 404 not_connected' do
    connection.update!(status: 'invalid')

    pedir

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('not_connected')
  end

  it 'sem a flag dos comentários de nenhuma rede: 404' do
    account.disable_features!('meta_ads_comentarios_instagram', 'meta_ads_comentarios_facebook')

    pedir

    expect(response).to have_http_status(:not_found)
  end

  it 'sem meta_ads_gestao: 404' do
    account.disable_features!('meta_ads_gestao')

    pedir

    expect(response).to have_http_status(:not_found)
  end

  it 'sem a flag do cuidado: 404' do
    account.disable_features!('meta_ads_comentarios_ia')

    pedir

    expect(response).to have_http_status(:not_found)
  end

  it 'agente sem a chave de ver Anúncios: 403' do
    agente = create(:user, account: account, role: :agent)

    pedir(agente)

    expect(response).to have_http_status(:forbidden)
  end

  it 'função personalizada com meta_ads_view: vê a lista' do
    papel = create(:custom_role, account: account, permissions: ['meta_ads_view'])
    pessoa = create(:user, account: account, role: :agent)
    pessoa.account_users.find_by(account: account).update!(custom_role: papel)

    pedir(pessoa)

    expect(response).to have_http_status(:ok)
  end
end
