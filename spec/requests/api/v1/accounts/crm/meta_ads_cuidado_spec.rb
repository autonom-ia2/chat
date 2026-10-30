require 'rails_helper'

# IA cuida dos comentários do anúncio (#2212, B2): as guardas das abas de comentários do anúncio, mais a flag
# meta_ads_comentarios_ia; o alvo vem do criativo (redes, posts e caixas); ligar, prévia, "Ler e mandar" e o selo.
RSpec.describe 'CRM meta_ads_connection: IA cuida dos comentários do anúncio', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:ad_id) { '120254710382770416' }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/ads/#{ad_id}" }
  let(:media_id) { '17900000000000001' }
  let(:story_id) { '555000111_777000222' }
  let(:ig_id) { '17841400000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo') }
  let(:corpo) do
    { message: 'Oi! O e-book sai por R$ 29. Te mando o link?', para_quem: 'Quem pedir o e-book', phrases: ['Te chamei no privado'],
      status: 'on' }
  end

  def comentario(id, text, horas: 1)
    { id: id, text: text, timestamp: horas.hours.ago.iso8601, from: { id: "f#{id}", username: "pessoa#{id}" } }
  end

  def stub_anuncio(creative, account_id: '2196424464528988')
    body = { id: ad_id, account_id: account_id, creative: creative }.to_json
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({})).to_return(status: 200, headers: json, body: body)
  end

  # A criação da caixa pela factory inscreve o app (subscribed_apps): não é chamada do cuidado.
  def meta_call
    a_request(:any, /graph\.(facebook|instagram)\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  before do
    Rails.cache.clear
    account.enable_features!('meta_ads_gestao', 'meta_ads_comentarios_instagram', 'meta_ads_comentarios_ia')
    create_meta_ads_insights_connection(account)
    stub_anuncio({ effective_instagram_media_id: media_id, instagram_user_id: ig_id, effective_object_story_id: story_id })
    data = [comentario('101', 'Quero o e-book'), comentario('102', 'Lindo!'), comentario('103', 'Valor?', horas: 24 * 9)]
    stub_request(:get, %r{#{ig}/#{media_id}/comments}).to_return(status: 200, headers: json, body: { data: data }.to_json)
    stub_request(:get, %r{#{ig}/#{media_id}\?}).to_return(status: 200, headers: json, body: { comments_count: data.size }.to_json)
  end

  it 'sem a flag meta_ads_comentarios_ia, sem a gestão ou sem a flag de nenhuma rede: 404 sem chamar a Meta' do
    [%w[meta_ads_comentarios_ia], %w[meta_ads_gestao], %w[meta_ads_comentarios_instagram]].each do |flags|
      account.disable_features!(*flags)

      get "#{base}/cuidado", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      account.enable_features!(*flags)
    end
    expect(meta_call).not_to have_been_made
  end

  it 'antes de ligar: só a rede com flag, caixa e post (o Facebook está desligado), com o privado liberado no Instagram' do
    get "#{base}/cuidado", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'ready', 'network' => 'instagram', 'private_available' => true,
                                            'care' => 'off', 'unanswered' => 2, 'older' => 1, 'inbox_id' => canal.inbox.id)
    expect(response.parsed_body['to_see'].map { |item| [item['id'], item['kind']] }).to eq([%w[101 waiting], %w[102 waiting], %w[103 older]])
  end

  it 'liga e grava o cuidado do anúncio com os posts do criativo, e a Auditoria sem texto' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('care' => 'on', 'para_quem' => 'Quem pedir o e-book')
    expect(Crm::MetaAdsCommentCare.sole).to have_attributes(target_kind: 'ad', target_id: ad_id, network: 'instagram',
                                                            post_ids: [media_id], status: 'on', created_by_id: admin.id)
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_comment_care').sole
    expect(audit.audited_changes).to eq('networks' => ['instagram'], 'ad_id' => ad_id, 'action' => 'save', 'status' => 'on')
  end

  it 'o motor acha o cuidado do anúncio pelo id do anúncio e pelo post do criativo' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json
    care = Crm::MetaAdsCommentCare.sole

    expect(Crm::MetaAdsCommentCare.cuidando(account_id: account.id, network: 'instagram', post_id: nil, ad_id: ad_id)).to eq(care)
    expect(Crm::MetaAdsCommentCare.cuidando(account_id: account.id, network: 'instagram', post_id: media_id, ad_id: nil)).to eq(care)
  end

  it 'nas duas redes, com a caixa da Página: o alvo leva as duas redes, os dois posts do criativo e a caixa de cada uma' do
    account.enable_features!('meta_ads_comentarios_facebook')
    pagina = create(:inbox, account: account, channel: build(:channel_facebook_page, account: account, page_id: '555000111'))
    anuncio = Crm::MetaAds::ComentariosIa::Anuncio.ler(Crm::MetaAdsConnection.sole, ad_id)

    expect(anuncio.alvo).to eq('kind' => 'ad', 'ad_id' => ad_id, 'networks' => %w[instagram facebook], 'post_ids' => [media_id, story_id])
    expect(anuncio.redes.transform_values { |rede| rede[:inbox].id }).to eq('instagram' => canal.inbox.id, 'facebook' => pagina.id)
  end

  it 'só o Facebook ligado e a Página sem caixa na conta: 422 no_inbox; sem post em rede ligada: 422 no_post' do
    account.disable_features!('meta_ads_comentarios_instagram')
    account.enable_features!('meta_ads_comentarios_facebook')

    get "#{base}/cuidado", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to eq('no_inbox')

    stub_anuncio({ effective_instagram_media_id: media_id, instagram_user_id: ig_id })
    get "#{base}/cuidado", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('no_post')
  end

  it 'anúncio de outra conta de anúncios: 404, sem ler os comentários' do
    stub_anuncio({ effective_instagram_media_id: media_id, instagram_user_id: ig_id }, account_id: '999')

    get "#{base}/cuidado", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:get, /graph\.instagram\.com/)).not_to have_been_made
  end

  it '"Ler e mandar": põe os comentários de até 7 dias na fila do motor com a caixa, o post e o anúncio' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json
    perform_enqueued_jobs(only: Crm::MetaAds::ComentariosIa::LerAntigosJob) do
      post "#{base}/cuidado/ler_antigos", headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:ok)
    cuidar = enqueued_jobs.select { |job| job['job_class'] == 'Crm::MetaAds::ComentariosIa::CuidarJob' }
    expect(cuidar.map { |job| job['arguments'].first['comment_id'] }).to eq(%w[101 102])
    expect(cuidar.first['arguments'].first).to include('network' => 'instagram', 'inbox_id' => canal.inbox.id, 'post_id' => media_id,
                                                       'ad_id' => ad_id)
    expect(cuidar.first['arguments'].first.keys).not_to include('text', 'from_name')

    post "#{base}/cuidado/ler_antigos", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['error']).to eq('already_read')
  end

  it 'prévia: decide com o "para quem" do dono' do
    classificador = instance_double(Crm::MetaAds::ComentariosIa::Classificador)
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:decidir) { |texto| { 'Quero o e-book' => 'private', 'Lindo!' => 'no_reply' }[texto] }

    post "#{base}/cuidado/previa", params: { para_quem: 'Quem pedir o e-book' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('recebe' => include('text' => 'Quero o e-book'), 'nao' => include('text' => 'Lindo!'))
  end

  it 'resumo: na primeira vez, está lendo' do
    get "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/ads/#{ad_id}/resumo", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('status' => 'reading')
  end

  it 'o selo: o estado do cuidado de cada anúncio, só do banco' do
    put "#{base}/cuidado", params: corpo, headers: admin.create_new_auth_token, as: :json

    get "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/cuidados", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['cuidados']).to eq([{ 'ad_id' => ad_id, 'care' => 'on' }])
  end

  context 'without meta_ads_manage (só meta_ads_view)' do
    let(:agente) { create(:user, account: account, role: :agent) }

    before do
      allow(Pundit).to receive(:policy!).and_call_original
      allow(Pundit).to receive(:policy!).with(anything, Crm::MetaAdsConnection)
                                        .and_return(instance_double(Crm::MetaAdsConnectionPolicy, show?: true, update?: false))
    end

    it 'quem vê a caixa vê o painel, mas não liga, não pede prévia nem "Ler e mandar"' do
      create(:inbox_member, user: agente, inbox: canal.inbox)

      get "#{base}/cuidado", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      put "#{base}/cuidado", params: corpo, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/cuidado/previa", params: { para_quem: 'x' }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base}/cuidado/ler_antigos", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAdsCommentCare.count).to eq(0)
    end

    it 'quem não vê a caixa do Instagram do anúncio: 403 not_inbox_member, sem ler os comentários' do
      get "#{base}/cuidado", headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('not_inbox_member')
      expect(a_request(:get, /graph\.instagram\.com/)).not_to have_been_made
    end
  end

  it 'agente comum, sem meta_ads_view: 403' do
    agente = create_crm_agent(account: account).first

    get "#{base}/cuidado", headers: agente.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
