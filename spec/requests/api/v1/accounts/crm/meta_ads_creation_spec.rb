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
    expect(response.parsed_body['budget']).to include('level' => 'adset', 'amount' => '30.00', 'active_ads_count' => 1)
  end

  it 'muda o orçamento e grava na Auditoria o antes e o depois, sem o token' do
    stub_budget
    stub_request(:post, meta_graph_url(adset_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    patch "#{path}/ads/#{ad_id}/budget", params: { amount: '40', end_time: nil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_budget_change').last
    expect(audit.user).to eq(admin)
    expect(audit.audited_changes).to include('ad_id' => ad_id, 'amount' => %w[30.00 40.00])
    expect(audit.audited_changes.to_json).not_to include(MetaAdsHelpers::TEST_TOKEN)
  end

  it 'valor fora do limite: 422 invalid_amount' do
    stub_budget

    patch "#{path}/ads/#{ad_id}/budget", params: { amount: '1000' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('invalid_amount')
  end

  it 'valor com mais de 2 casas: 422 invalid_amount, sem chamar a Meta' do
    params = { idempotency_key: SecureRandom.uuid, name: 'Bolo', destination: 'WEBSITE', site_url: 'https://loja.com.br',
               site_action: 'SHOP_NOW', page_id: '110', media: { kind: 'image', hash: 'abc' }, text: 'Bolo', placement: 'AUTO',
               region: 'BR', age_min: 18, age_max: 65, daily_amount: '20.005', start_date: '2026-10-27' }

    post "#{path}/ads", params: params, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_amount', 'nothing_created' => true)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'falha ao criar devolve o código e se nada foi criado' do
    params = { idempotency_key: SecureRandom.uuid, name: 'Bolo', destination: 'MESSENGER' }

    post "#{path}/ads", params: params, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_destination', 'nothing_created' => true)
  end

  it 'o mesmo pedido de outra tentativa: a resposta leva a chave dela (não confirmada 422, em andamento 409)' do
    twin = SecureRandom.uuid
    service = instance_double(Crm::MetaAds::Creation::NewAd)
    allow(Crm::MetaAds::Creation::NewAd).to receive(:new).and_return(service)
    unconfirmed = Crm::MetaAds::Creation::Error.new('unconfirmed', nothing_created: false, attempt_key: twin)
    allow(service).to receive(:create!).and_raise(unconfirmed)

    post "#{path}/ads", params: { idempotency_key: SecureRandom.uuid }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'unconfirmed', 'nothing_created' => false, 'idempotency_key' => twin)

    allow(service).to receive(:create!).and_raise(Crm::MetaAds::Creation::Error.new('in_progress', attempt_key: twin))
    post "#{path}/ads", params: { idempotency_key: SecureRandom.uuid }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('error' => 'in_progress', 'idempotency_key' => twin)
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

  describe 'impulsionar post (#2339): os posts da Página escolhida e o criar com o post' do
    let(:page_id) { '110000000002161' }

    before do
      stub_graph('me/permissions', { data: %w[ads_management pages_manage_ads].map { |name| { permission: name, status: 'granted' } } })
      stub_graph('me/accounts', { data: [{ id: page_id, name: 'Loja Exemplo', instagram_business_account: { id: '178', username: 'loja' } }] })
      stub_graph(page_id, { id: page_id, access_token: 'token-da-pagina-2339' }, fields: 'access_token')
      cover = { id: "#{page_id}_901", message: 'Oi', is_eligible_for_promotion: true, attachments: { data: [{ type: 'cover_photo' }] } }
      stub_graph("#{page_id}/published_posts", { data: [cover] })
      stub_graph('178/media', { data: [{ id: '1790', caption: 'Vestidos', boost_eligibility_info: { eligible_to_boost: true } }] })
    end

    it 'traz os posts da Página e do Instagram dela; capa vem apagada com o motivo' do
      get "#{path}/boost_posts", params: { page_id: page_id }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['posts'].map { |post| post.slice('id', 'eligible', 'reason') })
        .to eq([{ 'id' => "#{page_id}_901", 'eligible' => false, 'reason' => 'profile_or_cover' }])
      expect(body['instagram_posts'].map { |post| post.slice('id', 'eligible') }).to eq([{ 'id' => '1790', 'eligible' => true }])
      expect(body['posts_error']).to be_nil
    end

    it 'Página que o token não alcança: 422 invalid_page, sem ler posts' do
      get "#{path}/boost_posts", params: { page_id: '999' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_page')
      expect(a_request(:get, meta_graph_url('999/published_posts')).with(query: hash_including({}))).not_to have_been_made
    end

    it 'agente comum não lê os posts (403), sem chamar a Meta' do
      get "#{path}/boost_posts", params: { page_id: page_id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'o criar recebe o post escolhido' do
      service = instance_double(Crm::MetaAds::Creation::NewAd, created_now: true)
      allow(Crm::MetaAds::Creation::NewAd).to receive(:new).and_return(service)
      allow(service).to receive(:create!).and_return(ad_id: ad_id, name: 'Impulsionar', status: 'PAUSED', budget: {})

      post "#{path}/ads", params: { kind: 'post', post_source: 'instagram', post_id: '1790', page_id: page_id },
                          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(service).to have_received(:create!)
        .with(hash_including('kind' => 'post', 'post_source' => 'instagram', 'post_id' => '1790', 'page_id' => page_id))
    end
  end

  describe 'ativar (ponto 6): tudo nasce pausado, e ativar liga campanha, grupo e anúncio' do
    let(:campaign_id) { '120000000000000001' }
    let!(:record) do
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: SecureRandom.uuid, status: 'created', name: 'Bolo',
                                        ad_id: ad_id, campaign_id: campaign_id, adset_id: adset_id,
                                        ad_account_id: connection.ad_account_id)
    end

    def stub_level(id, accepted: true, reread: 'ACTIVE')
      turn_on = stub_request(:post, meta_graph_url(id)).with(body: { 'status' => 'ACTIVE' })
      if accepted
        turn_on.to_return(status: 200, body: { success: true }.to_json, headers: json)
      else
        turn_on.to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      end
      stub_graph(id, { id: id, status: reread, effective_status: reread }, fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS)
      stub_request(:post, meta_graph_url(id)).with(body: { 'status' => 'PAUSED' })
                                             .to_return(status: 200, body: { success: true }.to_json, headers: json)
    end

    def activate!
      post "#{path}/ads/#{ad_id}/status", params: { status: 'ACTIVE' }, headers: admin.create_new_auth_token, as: :json
    end

    def turned_on(id)
      a_request(:post, meta_graph_url(id)).with(body: { 'status' => 'ACTIVE' })
    end

    def paused_back(id)
      a_request(:post, meta_graph_url(id)).with(body: { 'status' => 'PAUSED' })
    end

    # Antes de ligar, a situação do anúncio: pausado e fora de análise (#2354).
    before do
      stub_permissions
      stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                               .to_return(status: 200, headers: json,
                                                          body: { id: ad_id, status: 'PAUSED', effective_status: 'PAUSED' }.to_json)
    end

    it 'liga os três, em ordem, relendo cada um, e marca como ativado' do
      [campaign_id, adset_id, ad_id].each { |id| stub_level(id) }

      activate!

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'ACTIVE', 'held_by' => nil)
      expect([turned_on(campaign_id), turned_on(adset_id), turned_on(ad_id)]).to all(have_been_made.once)
      expect(record.reload).to have_attributes(activated_at: be_present, switching_at: nil)
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_status').last.audited_changes)
        .to include('ad_id' => ad_id, 'campaign_id' => campaign_id, 'adset_id' => adset_id, 'status' => 'ACTIVE')
    end

    # #2354: a doc da Meta não diz se dá para ligar um anúncio durante a análise. Não oferecemos.
    it 'anúncio em análise da Meta: in_review, sem ligar nada' do
      stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                               .to_return(status: 200, headers: json,
                                                          body: { id: ad_id, status: 'PAUSED', effective_status: 'IN_PROCESS' }.to_json)

      activate!

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('in_review')
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
      expect(record.reload).to have_attributes(activated_at: nil, switching_at: nil)
    end

    it 'sem conseguir ler a situação do anúncio: meta_unavailable, sem ligar nada' do
      stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                               .to_return(status: 500, headers: json, body: meta_graph_error(1).to_json)

      activate!

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('meta_unavailable')
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
      expect(record.reload).to have_attributes(activated_at: nil, switching_at: nil)
    end

    it 'segundo clique enquanto o primeiro liga: in_progress, sem chamar a Meta' do
      record.update!(switching_at: 1.minute.ago)

      activate!

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('in_progress')
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
      expect(a_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))).not_to have_been_made
    end

    it 'trava esquecida (processo caiu) há mais de 3 minutos não prende o anúncio' do
      record.update!(switching_at: 4.minutes.ago)
      [campaign_id, adset_id, ad_id].each { |id| stub_level(id) }

      activate!

      expect(response).to have_http_status(:ok)
      expect(record.reload.switching_at).to be_nil
    end

    it 'a Meta ligou os três e só a gravação local falhou: responde sucesso e grava a Auditoria' do
      [campaign_id, adset_id, ad_id].each { |id| stub_level(id) }
      allow_any_instance_of(Crm::MetaAdsCreatedObject).to receive(:update!) # rubocop:disable RSpec/AnyInstance
        .with(hash_including(:activated_at)).and_raise(ActiveRecord::ActiveRecordError)

      activate!

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('ACTIVE')
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_status').last.audited_changes)
        .to include('ad_id' => ad_id, 'campaign_id' => campaign_id, 'adset_id' => adset_id, 'status' => 'ACTIVE')
    end

    it 'falha no grupo: volta a campanha (e o grupo) para pausado, não liga o anúncio e responde o erro' do
      stub_level(campaign_id)
      stub_level(adset_id, accepted: false)
      stub_level(ad_id)

      activate!

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('meta_refused')
      expect(paused_back(campaign_id)).to have_been_made.once
      expect(paused_back(adset_id)).to have_been_made.once
      expect(turned_on(ad_id)).not_to have_been_made
      expect(record.reload).to have_attributes(activated_at: nil, switching_at: nil)
    end

    it 'o anúncio ligou mas a releitura não confirma: volta os três para pausado' do
      stub_level(campaign_id)
      stub_level(adset_id)
      stub_level(ad_id, reread: 'PAUSED')

      activate!

      expect(response).to have_http_status(:unprocessable_entity)
      expect([paused_back(campaign_id), paused_back(adset_id), paused_back(ad_id)]).to all(have_been_made.once)
    end

    it 'sem conseguir voltar: meta_partial, e a Auditoria registra o que ficou ligado' do
      stub_level(campaign_id)
      stub_level(adset_id, accepted: false)
      stub_request(:post, meta_graph_url(campaign_id)).with(body: { 'status' => 'PAUSED' })
                                                      .to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)

      activate!

      expect(response.parsed_body['error']).to eq('meta_partial')
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_activate_partial').last.audited_changes)
        .to eq('active' => { 'campaign' => campaign_id })
    end

    it 'anúncio que não foi criado aqui: a ativação de sempre (só o anúncio) e o aviso de quem segura' do
      record.destroy!
      stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, status: 'PAUSED', effective_status: 'PAUSED' },
                 fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS)
      stub_graph(ad_id, { success: true }, verb: :post)
      stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, adset: { id: adset_id, effective_status: 'ACTIVE' },
                          campaign: { id: campaign_id, effective_status: 'PAUSED' } }, fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)

      activate!

      expect(response.parsed_body).to eq('status' => 'ACTIVE', 'held_by' => 'campaign')
      expect(turned_on(campaign_id)).not_to have_been_made
    end

    # Pedido da Funções no PR 1: a linha de outra conta da plataforma com o mesmo anúncio não liga campanha nem grupo.
    it 'linha de outra conta da plataforma com o mesmo anúncio: a ativação de sempre, sem tocar campanha e grupo' do
      record.update!(account: create(:account))
      stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, status: 'PAUSED', effective_status: 'PAUSED' },
                 fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS)
      stub_graph(ad_id, { success: true }, verb: :post)
      stub_graph(ad_id, { id: ad_id, account_id: connection.ad_account_id, adset: { id: adset_id, effective_status: 'ACTIVE' },
                          campaign: { id: campaign_id, effective_status: 'PAUSED' } }, fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS)

      activate!

      expect(response.parsed_body).to eq('status' => 'ACTIVE', 'held_by' => 'campaign')
      expect(turned_on(campaign_id)).not_to have_been_made
      expect(turned_on(adset_id)).not_to have_been_made
      expect(record.reload.activated_at).to be_nil
    end
  end

  describe 'pausar anúncio criado aqui: pausa anúncio, grupo e campanha, nessa ordem, relendo cada um' do
    let(:campaign_id) { '120000000000000001' }
    let!(:record) do
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: SecureRandom.uuid, status: 'created', name: 'Bolo',
                                        ad_id: ad_id, campaign_id: campaign_id, adset_id: adset_id,
                                        ad_account_id: connection.ad_account_id, activated_at: 1.day.ago)
    end
    let(:order) { [] }

    def stub_pause(id, accepted: true, reread: 'PAUSED')
      stub_request(:post, meta_graph_url(id)).with(body: { 'status' => 'PAUSED' }).to_return do
        order << id
        accepted ? { status: 200, body: { success: true }.to_json, headers: json } : { status: 400, body: meta_graph_error(1).to_json, headers: json }
      end
      stub_graph(id, { id: id, status: reread, effective_status: reread }, fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS)
    end

    def pause!
      post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: admin.create_new_auth_token, as: :json
    end

    before { stub_permissions }

    it 'pausa os três, do anúncio para a campanha, e a Auditoria guarda os três ids' do
      [ad_id, adset_id, campaign_id].each { |id| stub_pause(id) }

      pause!

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'PAUSED')
      expect(order).to eq([ad_id, adset_id, campaign_id])
      expect(a_request(:post, /graph\.facebook\.com/).with(body: { 'status' => 'ACTIVE' })).not_to have_been_made
      expect(record.reload.switching_at).to be_nil
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_ad_status').last.audited_changes)
        .to include('ad_id' => ad_id, 'campaign_id' => campaign_id, 'adset_id' => adset_id, 'status' => 'PAUSED')
    end

    it 'falha no grupo: pause_partial, a Auditoria registra o que pode ter ficado ligado, e nada é religado' do
      stub_pause(ad_id)
      stub_pause(adset_id, accepted: false)
      stub_pause(campaign_id)

      pause!

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('pause_partial')
      expect(order).to eq([ad_id, adset_id])
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_pause_partial').last.audited_changes)
        .to eq('active' => { 'adset' => adset_id, 'campaign' => campaign_id })
      expect(a_request(:post, /graph\.facebook\.com/).with(body: { 'status' => 'ACTIVE' })).not_to have_been_made
    end

    it 'a releitura do anúncio não confirma a pausa: o erro da Meta, sem seguir para o grupo' do
      stub_pause(ad_id, reread: 'ACTIVE')
      stub_pause(adset_id)

      pause!

      expect(response.parsed_body['error']).to eq('meta_refused')
      expect(order).to eq([ad_id])
      expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_pause_partial').last.audited_changes)
        .to eq('active' => { 'ad' => ad_id, 'adset' => adset_id, 'campaign' => campaign_id })
    end
  end
end
