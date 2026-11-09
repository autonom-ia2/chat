require 'rails_helper'

# Cuidar do anúncio (#2778): duplicar e trocar a foto ou o texto, só em anúncio criado pelo Chat2You (opção a do Rodrigo,
# 09/11). Sem a flag meta_ads_criar, 404 sem chamar a Meta; agente comum, 403; anúncio de fora, 404 ad_not_found. A
# cópia nasce pausada, com campanha e grupo próprios, e a mesma chave não copia duas vezes. A Meta é sempre stubada.
RSpec.describe 'CRM meta_ads_connection cuidar do anúncio (#2778)', type: :request do
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
  let!(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_id) { '120000000000216101' }
  let(:adset_id) { '120000000000021611' }
  let(:key) { SecureRandom.uuid }
  let!(:source) do
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: SecureRandom.uuid, status: 'created', name: 'Bolo de pote',
                                      ad_id: ad_id, campaign_id: campaign_id, adset_id: adset_id, creative_id: creative_id,
                                      ad_account_id: connection.ad_account_id, activated_at: 1.day.ago)
  end
  let(:spec_image) do
    { object_story_spec: { page_id: '111', link_data: { message: 'Texto antigo', image_hash: 'old-hash', picture: 'https://x/old.jpg',
                                                        link: 'https://api.whatsapp.com/send',
                                                        call_to_action: { type: 'WHATSAPP_MESSAGE' } } },
      url_tags: 'utm_source=meta', thumbnail_url: 'https://x/thumb.jpg' }
  end

  def json = { 'Content-Type' => 'application/json' }
  def campaign_id = '120000000000000001'
  def creative_id = '120000000000000501'
  def copy_campaign = '120000000000000002'
  def copy_adset = '120000000000021612'
  def copy_ad = '120000000000216102'
  def new_creative = '120000000000000502'

  before do
    travel_to Time.zone.parse('2026-11-09 12:00:00 -0300')
    account.enable_features!('meta_ads_criar', 'meta_ads_gestao')
  end

  def stub_graph(id, body, fields: nil)
    stub_request(:get, meta_graph_url(id)).with(query: fields ? hash_including(fields: fields) : hash_including({}))
                                          .to_return(status: 200, body: body.to_json, headers: json)
  end

  def stub_post(id, body, status: 200)
    stub_request(:post, meta_graph_url(id)).to_return(status: status, body: body.to_json, headers: json)
  end

  def stub_budget(end_time: '2026-11-30T23:59:00-0300')
    stub_graph('me/permissions', { data: [{ permission: 'ads_management', status: 'granted' }] })
    stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, campaign: { id: campaign_id, name: 'Vendas [abc]' },
                        adset: { id: adset_id, name: 'Público', daily_budget: '3000', start_time: '2026-10-01T09:00:00-0300',
                                 end_time: end_time } },
               fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)
    stub_graph("#{adset_id}/ads", { data: [{ effective_status: 'ACTIVE' }] })
    stub_graph("act_#{connection.ad_account_id}", { currency: 'BRL' })
  end

  def stub_copy_calls(fail_adset: false)
    stub_post("#{campaign_id}/copies", { copied_campaign_id: copy_campaign })
    stub_post("#{adset_id}/copies", fail_adset ? meta_graph_error(100) : { copied_adset_id: copy_adset }, status: fail_adset ? 400 : 200)
    stub_post("act_#{connection.ad_account_id}/ads", { id: copy_ad })
    [copy_campaign, copy_adset, copy_ad].each do |id|
      stub_graph(id, { id: id, status: 'PAUSED', effective_status: 'PAUSED' }, fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS)
    end
  end

  def copy!(body = {}, user: admin)
    post "#{path}/ads/#{ad_id}/copies", params: { idempotency_key: key }.merge(body), headers: user.create_new_auth_token, as: :json
  end

  it 'sem a flag responde 404 e não chama a Meta' do
    account.disable_features!('meta_ads_criar')

    copy!
    expect(response).to have_http_status(:not_found)
    put "#{path}/ads/#{ad_id}/creative", params: { idempotency_key: key, text: 'Oi' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'agente comum não duplica nem troca (403)' do
    copy!(user: agent)
    expect(response).to have_http_status(:forbidden)
    put "#{path}/ads/#{ad_id}/creative", params: { idempotency_key: key, text: 'Oi' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'anúncio que não foi criado aqui: 404 ad_not_found, sem chamar a Meta (opção a)' do
    post "#{path}/ads/999999/copies", params: { idempotency_key: key }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'ad_not_found')
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'duplica: campanha e grupo copiados pausados, anúncio novo com o mesmo criativo, na Auditoria' do
    stub_budget
    stub_copy_calls

    copy!

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('ad_id' => copy_ad, 'name' => 'Bolo de pote - Cópia', 'status' => 'PAUSED', 'in_review' => false,
                                            'budget' => include('kind' => 'daily', 'amount' => '30.00', 'active_ads_count' => 0,
                                                                'level' => 'adset'))
    mark = key.first(8)
    expect(a_request(:post, meta_graph_url("#{campaign_id}/copies")).with(body: hash_including(
      'deep_copy' => 'false', 'status_option' => 'PAUSED',
      'rename_options' => { rename_strategy: 'ONLY_TOP_LEVEL_RENAME', rename_suffix: " - Cópia [#{mark}]" }.to_json
    ))).to have_been_made.once
    expect(a_request(:post, meta_graph_url("#{adset_id}/copies")).with(body: hash_including(
      'campaign_id' => copy_campaign, 'deep_copy' => 'false', 'status_option' => 'PAUSED', 'end_time' => '2026-11-30T23:59:00-0300'
    ))).to have_been_made.once
    expect(a_request(:post, meta_graph_url("act_#{connection.ad_account_id}/ads")).with(body: hash_including(
      'adset_id' => copy_adset, 'status' => 'PAUSED', 'creative' => { creative_id: creative_id }.to_json
    ))).to have_been_made.once
    expect(Crm::MetaAdsCreatedObject.find_by(idempotency_key: key))
      .to have_attributes(kind: 'copy', status: 'created', campaign_id: copy_campaign, adset_id: copy_adset, ad_id: copy_ad,
                          creative_id: creative_id, activated_at: nil)
    expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_copied').last.audited_changes)
      .to include('source_ad_id' => ad_id, 'ad_id' => copy_ad, 'campaign_id' => copy_campaign, 'new_creative' => false)
  end

  it 'a mesma chave devolve a mesma cópia, sem chamar a Meta de novo' do
    stub_budget
    stub_copy_calls
    copy!
    WebMock::RequestRegistry.instance.reset!

    copy!

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ad_id']).to eq(copy_ad)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_copied').count).to eq(1)
  end

  it 'trocar a foto (cria uma cópia): criativo novo a partir do de agora, com a foto e o texto novos' do
    stub_budget
    stub_copy_calls
    stub_graph(creative_id, spec_image, fields: Meta::AdsGraphClient::CREATIVE_SPEC_FIELDS)
    stub_post("act_#{connection.ad_account_id}/adcreatives", { id: new_creative })

    copy!({ creative: { text: 'Texto novo', media: { kind: 'image', hash: 'new-hash' } } })

    expect(response).to have_http_status(:ok)
    sent = nil
    expect(a_request(:post, meta_graph_url("act_#{connection.ad_account_id}/adcreatives")).with do |request|
      sent = Rack::Utils.parse_nested_query(request.body)
    end).to have_been_made.once
    link = JSON.parse(sent['object_story_spec'])['link_data']
    expect(link).to include('message' => 'Texto novo', 'image_hash' => 'new-hash', 'link' => 'https://api.whatsapp.com/send')
    expect(link).not_to have_key('picture')
    expect(sent).to include('name' => 'Bolo de pote - Cópia', 'url_tags' => 'utm_source=meta')
    expect(a_request(:post, meta_graph_url("act_#{connection.ad_account_id}/ads"))
      .with(body: hash_including('creative' => { creative_id: new_creative }.to_json))).to have_been_made.once
    expect(source.reload.creative_id).to eq(creative_id)
  end

  it 'a mesma chave de outra cópia (outro anúncio ou outro criativo): invalid_params, sem chamar a Meta' do
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: key, status: 'created', kind: 'copy', name: 'Outra',
                                      request_digest: 'x' * 64, ad_account_id: connection.ad_account_id, ad_id: '1')

    copy!

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_params')
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'vídeo no lugar de foto: invalid_media, nada criado' do
    stub_budget
    stub_graph(creative_id, spec_image, fields: Meta::AdsGraphClient::CREATIVE_SPEC_FIELDS)

    copy!({ creative: { text: 'Texto novo', media: { kind: 'video', video_id: '123', image_hash: 'capa' } } })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'invalid_media', 'nothing_created' => true)
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'o grupo falha: a campanha copiada é apagada e a tela pode dizer "nada foi criado"' do
    stub_budget
    stub_copy_calls(fail_adset: true)
    delete_copy = stub_request(:delete, meta_graph_url(copy_campaign)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    copy!

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'meta_refused', 'nothing_created' => true)
    expect(delete_copy).to have_been_made.once
    expect(Crm::MetaAdsCreatedObject.find_by(idempotency_key: key).status).to eq('rolled_back')
  end

  it 'o original já terminou: invalid_dates, sem copiar' do
    stub_budget(end_time: '2026-11-01T23:59:00-0300')

    copy!

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_dates')
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  describe 'trocar no próprio anúncio' do
    def swap!(body = { text: 'Texto novo', media: { kind: 'image', hash: 'new-hash' } })
      put "#{path}/ads/#{ad_id}/creative", params: { idempotency_key: key }.merge(body), headers: admin.create_new_auth_token, as: :json
    end

    # Ligado para todos (#2804, decisão do Rodrigo de 09/11): `POST /{ad_id}` com `creative` ({ creative_id }), como no
    # SDK oficial da Meta (Ad#api_update aceita `creative`). Recusa clara cai na cópia pausada, pela tela.
    context 'when ligado para todos' do
      before do
        stub_graph('me/permissions', { data: [{ permission: 'ads_management', status: 'granted' }] })
        stub_graph(creative_id, spec_image, fields: Meta::AdsGraphClient::CREATIVE_SPEC_FIELDS)
        stub_post("act_#{connection.ad_account_id}/adcreatives", { id: new_creative })
        stub_graph(ad_id, { id: ad_id, status: 'ACTIVE', effective_status: 'PENDING_REVIEW' }, fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS)
      end

      it 'cria o criativo, põe no anúncio e diz que a Meta analisa de novo; a mesma chave não troca duas vezes' do
        stub_post(ad_id, { success: true })

        swap!
        swap!

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('effective_status' => 'PENDING_REVIEW')
        expect(a_request(:post, meta_graph_url(ad_id)).with(body: { 'creative' => { creative_id: new_creative }.to_json }))
          .to have_been_made.once
        expect(source.reload.creative_id).to eq(new_creative)
        expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_creative_swapped').count).to eq(1)
      end

      it 'sem resposta ao pôr no anúncio: não apaga o criativo e não diz que ficou como estava' do
        stub_request(:post, meta_graph_url(ad_id)).to_timeout

        swap!

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'unconfirmed', 'nothing_created' => false)
        expect(a_request(:delete, meta_graph_url(new_creative))).not_to have_been_made

        swap!
        expect(response.parsed_body['error']).to eq('unconfirmed')
        expect(a_request(:post, meta_graph_url(ad_id))).to have_been_made.once
      end

      it 'a Meta recusa pôr no anúncio: apaga o criativo novo, o anúncio fica como estava e a tela oferece a cópia' do
        stub_post(ad_id, meta_graph_error(100), status: 400)
        drop = stub_request(:delete, meta_graph_url(new_creative)).to_return(status: 200, body: { success: true }.to_json, headers: json)

        swap!

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'swap_refused', 'nothing_created' => true)
        expect(drop).to have_been_made.once
        expect(source.reload.creative_id).to eq(creative_id)
      end

      it 'a Meta recusa criar o criativo novo: meta_refused, sem tocar no anúncio (a cópia também precisaria dele)' do
        stub_post("act_#{connection.ad_account_id}/adcreatives", meta_graph_error(100), status: 400)

        swap!

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'meta_refused', 'nothing_created' => true)
        expect(a_request(:post, meta_graph_url(ad_id))).not_to have_been_made
      end
    end
  end

  # A cópia ficou sem resposta da Meta e a busca pela marca veio vazia (#2804): a pessoa confere no Gerenciador e cria
  # de novo pela tela, com a mesma chave. Sem pedir, a mesma chave continua "não confirmada".
  describe 'cópia não confirmada' do
    before do
      stub_budget
      stub_graph("act_#{connection.ad_account_id}/campaigns", { data: [] })
      stub_request(:post, meta_graph_url("#{campaign_id}/copies")).to_timeout
    end

    it 'sem resposta da Meta: unconfirmed; a mesma chave sem pedir para recriar não copia de novo' do
      copy!
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'unconfirmed', 'nothing_created' => false)
      expect(Crm::MetaAdsCreatedObject.find_by(idempotency_key: key).status).to eq('unconfirmed')

      copy!
      expect(response.parsed_body['error']).to eq('unconfirmed')
      expect(a_request(:post, meta_graph_url("#{campaign_id}/copies"))).to have_been_made.once
    end

    it 'a pessoa pede para criar de novo: copia com a mesma chave e grava na Auditoria' do
      copy!
      stub_copy_calls

      copy!({ recreate_unconfirmed: true })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('ad_id' => copy_ad, 'status' => 'PAUSED')
      expect(Crm::MetaAdsCreatedObject.find_by(idempotency_key: key)).to have_attributes(kind: 'copy', status: 'created')
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_create_recreated').count).to eq(1)
    end

    it 'recriar sem uma tentativa não confirmada desta chave: invalid_params, sem chamar a Meta' do
      copy!({ recreate_unconfirmed: true })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_params')
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'a gestão diz se o anúncio foi criado aqui' do
    before do
      stub_graph('me/permissions', { data: [{ permission: 'ads_management', status: 'granted' }] })
      stub_graph(creative_id, spec_image, fields: Meta::AdsGraphClient::CREATIVE_SPEC_FIELDS)
    end

    def management(id)
      stub_graph(id, { id: id, name: 'Bolo', account_id: connection.ad_account_id, status: 'ACTIVE', effective_status: 'ACTIVE' },
                 fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS)
      get "#{path}/ads/#{id}/management", headers: admin.create_new_auth_token, as: :json
      response.parsed_body['management']
    end

    it 'criado aqui: created_here e a foto trocável no próprio anúncio' do
      expect(management(ad_id)).not_to have_key('can_swap_creative')
      expect(management(ad_id)).to include('created_here' => true, 'creative_kind' => 'image',
                                           'creative_image' => 'https://x/thumb.jpg', 'creative_text' => 'Texto antigo')
    end

    it 'criado fora: o cartão não aparece, nem o criativo é lido' do
      expect(management('120000000000999999')).to include(
        'created_here' => false, 'creative_kind' => nil,
        'ads_manager_url' => "https://adsmanager.facebook.com/adsmanager/manage/ads?act=#{connection.ad_account_id}&selected_ad_ids=120000000000999999"
      )
      expect(a_request(:get, meta_graph_url(creative_id)).with(query: hash_including({}))).not_to have_been_made
    end

    # Cada abertura do detalhe lia o criativo na Graph: gasta o limite de uso da Meta.
    it 'lê o criativo uma vez a cada 5 minutos por conta e anúncio' do
      management(ad_id)
      management(ad_id)
      expect(a_request(:get, meta_graph_url(creative_id)).with(query: hash_including({}))).to have_been_made.once

      travel 6.minutes
      expect(management(ad_id)).to include('creative_kind' => 'image')
      expect(a_request(:get, meta_graph_url(creative_id)).with(query: hash_including({}))).to have_been_made.twice
    end

    it 'duplicar apaga a leitura guardada do anúncio' do
      management(ad_id)
      stub_budget
      stub_copy_calls
      copy!
      expect(response).to have_http_status(:ok)

      management(ad_id)
      expect(a_request(:get, meta_graph_url(creative_id)).with(query: hash_including({}))).to have_been_made.twice
    end

    it 'trocar no anúncio apaga a leitura guardada' do
      management(ad_id)
      stub_post("act_#{connection.ad_account_id}/adcreatives", { id: new_creative })
      stub_post(ad_id, { success: true })
      stub_graph(ad_id, { id: ad_id, status: 'ACTIVE', effective_status: 'PENDING_REVIEW' }, fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS)
      stub_graph(new_creative, spec_image, fields: Meta::AdsGraphClient::CREATIVE_SPEC_FIELDS)
      put "#{path}/ads/#{ad_id}/creative", params: { idempotency_key: key, text: 'Novo' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      management(ad_id)
      expect(a_request(:get, meta_graph_url(new_creative)).with(query: hash_including({}))).to have_been_made.once
    end
  end
end
