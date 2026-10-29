require 'rails_helper'

# Anúncio novo (#2198, Fluxo 1 e os sete pontos): campanha, grupo e anúncio PAUSED explícito (decisão do Rodrigo,
# opção a), relidos e pausados de novo se não vierem pausados, chave de idempotência, revalidação no servidor e falha no
# meio desfazendo o começo.
RSpec.describe Crm::MetaAds::Creation::NewAd do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:act) { "act_#{connection.ad_account_id}" }
  let(:page_id) { '110000000002161' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:whatsapp_number) { '+5511900002161' }
  # O texto da tela Conexão › Destino (#2345), escrito à mão para o spec pegar mudança na fonte. Só vai no anúncio do site.
  let(:url_tags) do
    'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}&utm_id={{campaign.id}}'
  end
  # A campanha da tentativa leva a marca da chave no nome (os 8 primeiros caracteres).
  let(:campaign_name) { 'Bolo de pote · WhatsApp [a1b2c3d4]' }

  let(:draft) do
    {
      idempotency_key: 'a1b2c3d4-0000-4000-8000-000000002198', name: 'Bolo de pote · WhatsApp', destination: 'WHATSAPP', page_id: page_id,
      whatsapp_number: whatsapp_number, media: { kind: 'image', hash: 'abc123' }, cards: [],
      text: 'Bolo de pote a R$ 12. Chame no WhatsApp.', headline: 'Bolo de pote a R$ 12', ready_message: 'Quero um bolo',
      placement: 'AUTO', region: 'BR', states: [], age_min: 25, age_max: 45, special_category: false,
      daily_amount: '20', start_date: '2026-10-27', end_date: ''
    }
  end

  def ok(body)
    { status: 200, body: body.to_json, headers: json }
  end

  def stub_pages(instagram: nil)
    page = { id: page_id, name: 'Loja Exemplo' }
    page[:instagram_business_account] = instagram if instagram
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including('fields' => Meta::AdsGraphClient::PAGES_FIELDS))
                                                     .to_return(ok(data: [page]))
  end

  def stub_creation(campaign: ok(id: '900'), adset: ok(id: '901'), creative: ok(id: '902'), advert: ok(id: '903'))
    {
      campaign: stub_request(:post, meta_graph_url("#{act}/campaigns")).to_return(campaign),
      adset: stub_request(:post, meta_graph_url("#{act}/adsets")).to_return(adset),
      creative: stub_request(:post, meta_graph_url("#{act}/adcreatives")).to_return(creative),
      ad: stub_request(:post, meta_graph_url("#{act}/ads")).to_return(advert)
    }
  end

  # A releitura dos três níveis depois de criar. `ad_status:` muda só a situação do anúncio.
  def stub_reread(ad_status: 'PAUSED', ad_effective: ad_status)
    { '900' => %w[PAUSED PAUSED], '901' => %w[PAUSED PAUSED], '903' => [ad_status, ad_effective] }.each do |id, (status, effective)|
      stub_request(:get, meta_graph_url(id)).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                            .to_return(ok(id: id, status: status, effective_status: effective))
    end
  end

  def stub_currency(currency = 'BRL', timezone: nil)
    stub_request(:get, meta_graph_url(act)).with(query: hash_including({}))
                                           .to_return(ok({ id: act, currency: currency, timezone_name: timezone }.compact))
  end

  def stub_campaign_search(found = [], status: 200)
    response = status == 200 ? ok(data: found) : { status: status, body: meta_graph_error(1).to_json, headers: json }
    stub_request(:get, meta_graph_url("#{act}/campaigns"))
      .with(query: hash_including('filtering' => [{ field: 'name', operator: 'CONTAIN', value: 'a1b2c3d4' }].to_json))
      .to_return(response)
  end

  def form(request_signature)
    Rack::Utils.parse_nested_query(request_signature.body)
  end

  def create!(params = draft)
    described_class.new(connection, user: user).create!(params)
  end

  before do
    travel_to Time.zone.parse('2026-10-27 12:00:00 -0300')
    create(:channel_whatsapp, account: account, phone_number: whatsapp_number, validate_provider_config: false, sync_templates: false)
    stub_pages
    stub_currency
    stub_campaign_search
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(ok(data: %w[ads_management pages_manage_ads].map { |name| { permission: name, status: 'granted' } }))
  end

  # #2354: pela doc do Ad, anúncio novo passa pela análise da Meta antes. O cartão de criado não oferece Ativar então.
  it 'anúncio recém-criado em análise da Meta: a resposta diz in_review, da releitura que o criar já faz' do
    stub_creation
    stub_reread(ad_effective: 'IN_PROCESS')

    expect(create!).to include(ad_id: '903', status: 'PAUSED', in_review: true)
  end

  it 'cria campanha, grupo e anúncio PAUSED, com destino WhatsApp e público do Brasil' do
    stubs = stub_creation
    stub_reread

    result = create!

    expect(result).to include(ad_id: '903', name: 'Bolo de pote · WhatsApp', status: 'PAUSED', in_review: false)
    campaign_ok = lambda do |req|
      body = form(req)
      body['objective'] == 'OUTCOME_ENGAGEMENT' && body['status'] == 'PAUSED' && body['special_ad_categories'] == '[]' &&
        body['name'] == campaign_name
    end
    adset_ok = lambda do |req|
      body = form(req)
      targeting = JSON.parse(body['targeting'])
      body['status'] == 'PAUSED' && body['campaign_id'] == '900' && body['daily_budget'] == '2000' &&
        body['destination_type'] == 'WHATSAPP' && body['optimization_goal'] == 'CONVERSATIONS' &&
        JSON.parse(body['promoted_object']) == { 'page_id' => page_id, 'whatsapp_phone_number' => whatsapp_number } &&
        targeting['geo_locations'] == { 'countries' => ['BR'] } && targeting['age_min'] == 25 && targeting['age_max'] == 45 &&
        targeting['publisher_platforms'] == %w[facebook instagram] && body['end_time'].nil?
    end
    creative_ok = lambda do |req|
      spec = JSON.parse(form(req)['object_story_spec'])
      form(req)['url_tags'].nil? &&
        spec['page_id'] == page_id && spec.dig('link_data', 'image_hash') == 'abc123' &&
        spec.dig('link_data', 'call_to_action') == { 'type' => 'WHATSAPP_MESSAGE', 'value' => { 'app_destination' => 'WHATSAPP' } }
    end
    expect(stubs[:campaign].with(&campaign_ok)).to have_been_made.once
    expect(stubs[:adset].with(&adset_ok)).to have_been_made.once
    expect(stubs[:creative].with(&creative_ok)).to have_been_made.once
    expect(stubs[:ad].with { |req| form(req).values_at('status', 'adset_id') == %w[PAUSED 901] }).to have_been_made.once
    expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'created', campaign_id: '900', adset_id: '901',
                                                              creative_id: '902', ad_id: '903', user_id: user.id)
  end

  it 'anúncio que não voltou pausado é pausado na hora e fica na Auditoria (ponto 2)' do
    stub_creation
    stub_reread(ad_status: 'ACTIVE')
    pause = stub_request(:post, meta_graph_url('903')).with(body: { 'status' => 'PAUSED' }).to_return(ok(success: true))

    expect { create! }.to change { Audited.audit_class.where(auditable: account, action: 'meta_ads_create_repaused').count }.by(1)
    expect(pause).to have_been_made.once
    expect(Audited.audit_class.where(action: 'meta_ads_create_repaused').last.audited_changes)
      .to include('level' => 'ad', 'object_id' => '903', 'paused' => true)
  end

  it 'campanha que não voltou pausada também é pausada na hora (os três níveis)' do
    stub_creation
    stub_reread
    stub_request(:get, meta_graph_url('900')).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                             .to_return(ok(id: '900', status: 'ACTIVE', effective_status: 'ACTIVE'))
    pause = stub_request(:post, meta_graph_url('900')).with(body: { 'status' => 'PAUSED' }).to_return(ok(success: true))

    create!

    expect(pause).to have_been_made.once
    expect(Audited.audit_class.where(action: 'meta_ads_create_repaused').last.audited_changes).to include('level' => 'campaign')
  end

  it 'anúncio pausado na hora: in_review vem da releitura depois de pausar (#2354)' do
    stub_creation
    stub_reread
    stub_request(:get, meta_graph_url('903')).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                             .to_return(ok(id: '903', status: 'ACTIVE', effective_status: 'ACTIVE'),
                                                        ok(id: '903', status: 'PAUSED', effective_status: 'IN_PROCESS'))
    stub_request(:post, meta_graph_url('903')).with(body: { 'status' => 'PAUSED' }).to_return(ok(success: true))

    expect(create!).to include(in_review: true)
  end

  it 'a mesma chave de novo não chama a Meta (ponto 4): sem releitura, in_review false (#2354)' do
    stub_creation
    stub_reread(ad_effective: 'IN_PROCESS')
    expect(create!).to include(in_review: true)

    expect(create!).to include(in_review: false)
    expect(a_request(:get, meta_graph_url('903')).with(query: hash_including({}))).to have_been_made.once
  end

  it 'a mesma chave não cria duas campanhas (ponto 4)' do
    stubs = stub_creation
    stub_reread

    first = create!
    second = create!

    expect(second).to eq(first)
    expect(stubs[:campaign]).to have_been_made.once
  end

  it 'falha no criativo apaga a campanha e diz que nada foi criado (ponto 3)' do
    stub_creation(creative: { status: 400, body: meta_graph_error(100).to_json, headers: json })
    delete = stub_request(:delete, meta_graph_url('900')).to_return(ok(success: true))

    expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
      expect(e.code).to eq('meta_refused')
      expect(e.nothing_created).to be(true)
    }
    expect(delete).to have_been_made.once
    expect(Crm::MetaAdsCreatedObject.last.status).to eq('rolled_back')
  end

  it 'se nem apagar der, a campanha é arquivada e a tela não diz que nada foi criado' do
    stub_creation(advert: { status: 500, body: meta_graph_error(1).to_json, headers: json })
    stub_request(:delete, meta_graph_url('900')).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
    stub_request(:post, meta_graph_url('900')).with(body: { 'status' => 'ARCHIVED' })
                                              .to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
    stub_request(:get, meta_graph_url('900')).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                             .to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)

    expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
      expect(e.code).to eq('meta_unavailable')
      expect(e.nothing_created).to be(false)
    }
    expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'rollback_failed', campaign_id: '900')
  end

  it 'site: tráfego, link e botão escolhido, só em https' do
    stubs = stub_creation
    stub_reread
    site = draft.merge(destination: 'WEBSITE', site_url: 'https://lojaexemplo.com.br', site_action: 'SHOP_NOW', placement: 'INSTAGRAM')

    create!(site)

    expect(stubs[:campaign].with { |req| form(req)['objective'] == 'OUTCOME_TRAFFIC' }).to have_been_made
    adset_ok = lambda do |req|
      body = form(req)
      body['optimization_goal'] == 'LINK_CLICKS' && body['promoted_object'].nil? &&
        JSON.parse(body['targeting'])['publisher_platforms'] == ['instagram']
    end
    creative_ok = lambda do |req|
      action = JSON.parse(form(req)['object_story_spec']).dig('link_data', 'call_to_action')
      form(req)['url_tags'] == url_tags && action == { 'type' => 'SHOP_NOW', 'value' => { 'link' => 'https://lojaexemplo.com.br' } }
    end
    expect(stubs[:adset].with(&adset_ok)).to have_been_made
    expect(stubs[:creative].with(&creative_ok)).to have_been_made
  end

  it 'categoria especial marca crédito/seguro e trava a idade em 18 a 65' do
    stubs = stub_creation
    stub_reread

    create!(draft.merge(special_category: true, age_min: 30, age_max: 40))

    expect(stubs[:campaign].with { |req| form(req)['special_ad_categories'] == '["FINANCIAL_PRODUCTS_SERVICES"]' }).to have_been_made
    expect(stubs[:adset].with { |req| JSON.parse(form(req)['targeting']).values_at('age_min', 'age_max') == [18, 65] }).to have_been_made
  end

  it 'alguns estados viram as regiões da Meta' do
    stubs = stub_creation
    stub_reread
    stub_request(:get, meta_graph_url('search')).with(query: hash_including('q' => 'São Paulo', 'type' => 'adgeolocation'))
                                                .to_return(ok(data: [{ key: '460', name: 'São Paulo', type: 'region', country_code: 'BR' }]))

    create!(draft.merge(region: 'STATES', states: ['SP']))

    expect(stubs[:adset].with { |req| JSON.parse(form(req)['targeting'])['geo_locations'] == { 'regions' => [{ 'key' => '460' }] } })
      .to have_been_made
  end

  it 'carrossel vai em child_attachments' do
    stubs = stub_creation
    stub_reread

    create!(draft.merge(cards: [{ kind: 'image', hash: 'def456' }]))

    cards_ok = lambda do |req|
      JSON.parse(form(req)['object_story_spec']).dig('link_data', 'child_attachments').pluck('image_hash') == %w[abc123 def456]
    end
    expect(stubs[:creative].with(&cards_ok)).to have_been_made
  end

  it 'vídeo ainda em processamento na Meta: avisa antes de criar qualquer coisa' do
    stubs = stub_creation
    stub_request(:get, meta_graph_url('777')).with(query: { fields: 'status' }).to_return(ok(status: { video_status: 'processing' }))

    expect { create!(draft.merge(media: { kind: 'video', video_id: '777', image_hash: 'abc123' })) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('video_processing') }
    expect(stubs[:campaign]).not_to have_been_made
  end

  describe 'nova tentativa com a mesma chave (ponto 4)' do
    def leftover(status:, updated_at: Time.current)
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: draft[:idempotency_key], status: status,
                                        campaign_id: '800', updated_at: updated_at)
    end

    it 'o que ficou na Meta é apagado antes de criar de novo' do
      leftover(status: 'rollback_failed')
      undo = stub_request(:delete, meta_graph_url('800')).to_return(ok(success: true))
      stubs = stub_creation
      stub_reread

      expect(create!).to include(ad_id: '903')
      expect(undo).to have_been_made.once
      expect(stubs[:campaign]).to have_been_made.once
    end

    it 'se o que ficou na Meta não sai, recusa sem criar outra campanha' do
      leftover(status: 'rollback_failed')
      stub_request(:delete, meta_graph_url('800')).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      stub_request(:post, meta_graph_url('800')).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      stub_request(:get, meta_graph_url('800')).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                               .to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(false) }
      expect(stubs[:campaign]).not_to have_been_made
      # A linha volta para a situação de antes, com o id: a próxima tentativa confere de novo.
      expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'rollback_failed', campaign_id: '800')
    end

    def gone_campaign(reread_error)
      leftover(status: 'rollback_failed')
      stub_request(:delete, meta_graph_url('800')).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      stub_request(:post, meta_graph_url('800')).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      stub_request(:get, meta_graph_url('800')).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                               .to_return(status: 400, body: reread_error.to_json, headers: json)
    end

    it 'campanha que já não existe na Meta (100 com subcódigo 33) conta como desfeita: a chave não fica presa' do
      gone_campaign(meta_graph_error(100, 'Unsupported get request', subcode: 33))
      stubs = stub_creation
      stub_reread

      expect(create!).to include(ad_id: '903')
      expect(stubs[:campaign]).to have_been_made.once
    end

    it 'o 100 sem subcódigo é parâmetro inválido, não sumiço: continua presa, sem criar outra' do
      gone_campaign(meta_graph_error(100))
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(false) }
      expect(stubs[:campaign]).not_to have_been_made
      expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'rollback_failed', campaign_id: '800')
    end

    it 'campanha que a Meta ainda mostra viva e não deixa apagar: continua presa, sem criar outra' do
      leftover(status: 'rollback_failed')
      stub_request(:delete, meta_graph_url('800')).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      stub_request(:post, meta_graph_url('800')).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      stub_request(:get, meta_graph_url('800')).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                               .to_return(ok(id: '800', effective_status: 'ACTIVE'))
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(false) }
      expect(stubs[:campaign]).not_to have_been_made
    end

    it 'corrida A/B: B leu a mesma tentativa, mas A a pegou antes; B recebe in_progress e não desfaz nem cria' do
      row = leftover(status: 'rollback_failed')
      allow(Crm::MetaAdsCreatedObject).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        found = original.call(*args, **kwargs)
        conditions = kwargs.presence || args.first.to_h
        # A pega a linha entre a leitura de B (a da tentativa, sem filtro de situação) e o UPDATE condicional de B.
        if conditions.key?(:idempotency_key) && !conditions.key?(:status)
          row.update_columns(status: 'creating', updated_at: 1.second.from_now) # rubocop:disable Rails/SkipsModelValidations
        end
        found
      end
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('in_progress') }
      expect(a_request(:delete, meta_graph_url('800'))).not_to have_been_made
      expect(stubs[:campaign]).not_to have_been_made
    end

    it 'quem pega a linha a leva para creating antes de desfazer: outro pedido no meio do desfazer recebe in_progress' do
      leftover(status: 'rollback_failed')
      seen = nil
      allow_any_instance_of(Crm::MetaAds::Creation::CampaignUndo).to receive(:undo) do # rubocop:disable RSpec/AnyInstance
        seen = Crm::MetaAdsCreatedObject.last.status
        :undone
      end
      stub_creation
      stub_reread

      expect(create!).to include(ad_id: '903')
      expect(seen).to eq('creating')
    end

    it 'tentativa já desfeita refaz sem tentar apagar de novo' do
      leftover(status: 'rolled_back')
      stubs = stub_creation
      stub_reread

      expect(create!).to include(ad_id: '903')
      expect(a_request(:delete, meta_graph_url('800'))).not_to have_been_made
      expect(stubs[:campaign]).to have_been_made.once
    end

    it 'replay de anúncio já criado não chama a Meta nem para o fuso' do
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: draft[:idempotency_key], status: 'created', ad_id: '903')
      connection.update!(ad_account_timezone: nil)

      expect(create!).to include(ad_id: '903')
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'tentativa em andamento há pouco: in_progress, sem chamar a Meta para criar' do
      leftover(status: 'creating')
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('in_progress') }
      expect(stubs[:campaign]).not_to have_been_made
    end

    it 'tentativa presa sem o id da campanha: acha pela marca na Meta, apaga e refaz' do
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: draft[:idempotency_key], status: 'creating',
                                        name: draft[:name], updated_at: 11.minutes.ago)
      stub_campaign_search([{ id: '950', name: campaign_name, effective_status: 'ACTIVE' }])
      undo = stub_request(:delete, meta_graph_url('950')).to_return(ok(success: true))
      stubs = stub_creation
      stub_reread

      expect(create!).to include(ad_id: '903')
      expect(undo).to have_been_made.once
      expect(stubs[:campaign]).to have_been_made.once
    end

    def invalid(attribute, kind)
      row = Crm::MetaAdsCreatedObject.new
      row.errors.add(attribute, kind)
      ActiveRecord::RecordInvalid.new(row)
    end

    it 'corrida: outra linha com a mesma chave nasceu no mesmo instante → in_progress, não 500' do
      allow(Crm::MetaAdsCreatedObject).to receive(:create!).and_raise(invalid(:idempotency_key, :taken))
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('in_progress') }
      expect(stubs[:campaign]).not_to have_been_made
    end

    it 'outra validação que falha sobe como erro real, não como "em andamento"' do
      allow(Crm::MetaAdsCreatedObject).to receive(:create!).and_raise(invalid(:status, :inclusion))

      expect { create! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'tentativa presa há mais de 10 minutos sem campanha achada: vira não confirmada, nunca cria sem saber' do
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: draft[:idempotency_key], status: 'creating',
                                        name: draft[:name], updated_at: 11.minutes.ago)
      stub_campaign_search
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('unconfirmed') }
      expect(stubs[:campaign]).not_to have_been_made
      expect(Crm::MetaAdsCreatedObject.last.status).to eq('unconfirmed')
    end

    it 'tentativa presa há mais de 10 minutos é desfeita e refeita' do
      leftover(status: 'creating', updated_at: 11.minutes.ago)
      undo = stub_request(:delete, meta_graph_url('800')).to_return(ok(success: true))
      stub_creation
      stub_reread

      expect(create!).to include(ad_id: '903')
      expect(undo).to have_been_made.once
    end

    it 'devolver o que já existia não conta como criado agora' do
      stub_creation
      stub_reread
      first = described_class.new(connection, user: user)
      first.create!(draft)
      second = described_class.new(connection, user: user)
      second.create!(draft)

      expect([first.created_now, second.created_now]).to eq([true, nil])
    end
  end

  describe 'o pedido no digest' do
    def digest_of(params)
      Crm::MetaAds::Creation::Draft.new(draft.merge(params), account: account,
                                                             zone: ActiveSupport::TimeZone['America/Sao_Paulo']).validate!.digest
    end

    it 'estados são conjunto: SP→RJ e RJ→SP são o mesmo pedido; a chave e a liberação não entram' do
      sp_rj = digest_of(region: 'STATES', states: %w[SP RJ])

      expect(digest_of(region: 'STATES', states: %w[RJ SP SP])).to eq(sp_rj)
      expect(digest_of(region: 'STATES', states: %w[SP RJ], idempotency_key: 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e',
                       recreate_unconfirmed: true)).to eq(sp_rj)
      expect(digest_of(region: 'STATES', states: %w[SP])).not_to eq(sp_rj)
    end

    it 'Brasil todo ignora estados que vierem junto' do
      expect(digest_of(region: 'BR', states: %w[SP])).to eq(digest_of(region: 'BR', states: []))
    end

    it 'cartões do carrossel são sequência: outra ordem é outro anúncio' do
      first = { kind: 'image', hash: 'h1' }
      second = { kind: 'image', hash: 'h2' }

      expect(digest_of(cards: [first, second])).not_to eq(digest_of(cards: [second, first]))
    end
  end

  it 'erro inesperado no meio também desfaz o começo' do
    stub_creation
    delete = stub_request(:delete, meta_graph_url('900')).to_return(ok(success: true))
    allow(Crm::MetaAds::Creation::Story).to receive(:new).and_raise(NoMethodError)

    expect { create! }.to raise_error(NoMethodError)
    expect(delete).to have_been_made.once
    expect(Crm::MetaAdsCreatedObject.last.status).to eq('rolled_back')
  end

  it 'pausa que falha, mesmo com a Auditoria fora, desfaz tudo' do
    stub_creation
    stub_reread(ad_status: 'ACTIVE')
    stub_request(:post, meta_graph_url('903')).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
    delete = stub_request(:delete, meta_graph_url('900')).to_return(ok(success: true))
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(true) }
    expect(delete).to have_been_made.once
  end

  it 'sem o fuso da conta de anúncios guardado, lê na Meta e guarda antes de usar as datas' do
    connection.update!(ad_account_timezone: nil)
    stub_currency(timezone: 'America/Sao_Paulo')
    stub_creation
    stub_reread

    create!

    expect(connection.reload.ad_account_timezone).to eq('America/Sao_Paulo')
  end

  it 'busca de estado que volta só com outro nome não vira público' do
    stubs = stub_creation
    stub_request(:get, meta_graph_url('search')).with(query: hash_including('q' => 'Acre'))
                                                .to_return(ok(data: [{ key: '999', name: 'Acre Province', type: 'region', country_code: 'BR' }]))

    expect { create!(draft.merge(region: 'STATES', states: ['AC'])) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_audience') }
    expect(stubs[:campaign]).not_to have_been_made
  end

  it 'rascunho inválido não chama a Meta para nada, nem para ler o fuso' do
    connection.update!(ad_account_timezone: nil)

    expect { create!(draft.merge(daily_amount: '20.005')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_amount') }
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'valor com centavos vai para a Meta em centavos inteiros, sem float' do
    stubs = stub_creation
    stub_reread

    result = create!(draft.merge(daily_amount: '20.57'))

    expect(stubs[:adset].with { |req| form(req)['daily_budget'] == '2057' }).to have_been_made
    expect(result[:budget]['amount']).to eq('20.57')
  end

  describe 'moeda da conta de anúncios (só real)' do
    it 'conta em outra moeda: recusa antes de criar qualquer coisa' do
      stub_currency('USD')
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
        expect(e.code).to eq('currency_not_supported')
        expect(e.nothing_created).to be(true)
      }
      expect(stubs[:campaign]).not_to have_been_made
      expect(Crm::MetaAdsCreatedObject.count).to eq(0)
    end

    it 'sem conseguir ler a moeda: não cria' do
      stub_request(:get, meta_graph_url(act)).with(query: hash_including({}))
                                             .to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_unavailable') }
      expect(stubs[:campaign]).not_to have_been_made
    end
  end

  describe 'resposta da campanha perdida (tempo esgotado): a Meta é conferida pela marca no nome' do
    before do
      stub_creation
      stub_request(:post, meta_graph_url("#{act}/campaigns")).to_timeout
    end

    it 'a campanha existe: apaga e só então diz que nada foi criado' do
      stub_campaign_search([{ id: '950', name: campaign_name, effective_status: 'PAUSED' },
                            { id: '951', name: 'Outra campanha [a1b2c3d4] cópia', effective_status: 'ACTIVE' }])
      delete = stub_request(:delete, meta_graph_url('950')).to_return(ok(success: true))

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(true) }
      expect(delete).to have_been_made.once
      expect(a_request(:delete, meta_graph_url('951'))).not_to have_been_made
      expect(Crm::MetaAdsCreatedObject.last.status).to eq('rolled_back')
    end

    it 'busca vazia não é "nada criado": a tentativa fica não confirmada e a tela pede para conferir' do
      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
        expect(e.code).to eq('unconfirmed')
        expect(e.nothing_created).to be(false)
      }
      expect(a_request(:delete, /graph\.facebook\.com/)).not_to have_been_made
      expect(Crm::MetaAdsCreatedObject.last.status).to eq('unconfirmed')
    end

    describe 'nova tentativa com a mesma chave depois de não confirmada' do
      # A primeira tentativa fica não confirmada (tempo esgotado e busca vazia); qualquer outra coisa quebra o teste.
      def first_attempt_unconfirmed!
        create!
      rescue Crm::MetaAds::Creation::Error => e
        raise unless e.code == 'unconfirmed'
      else
        raise 'a primeira tentativa devia ficar não confirmada'
      end

      before do
        first_attempt_unconfirmed!
        stub_creation
        stub_reread
      end

      it 'busca vazia de novo: continua não confirmada e não cria' do
        expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('unconfirmed') }
        expect(a_request(:post, meta_graph_url("#{act}/campaigns"))).to have_been_made.once
      end

      it 'a campanha apareceu na busca: desfaz e cria de novo' do
        stub_campaign_search([{ id: '950', name: campaign_name, effective_status: 'PAUSED' }])
        delete = stub_request(:delete, meta_graph_url('950')).to_return(ok(success: true))

        expect(create!).to include(ad_id: '903')
        expect(delete).to have_been_made.once
      end

      it 'busca vazia mesmo depois de muito tempo: não cria sozinho (a Meta pode só estar atrasada)' do
        travel 2.hours

        expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('unconfirmed') }
        expect(a_request(:post, meta_graph_url("#{act}/campaigns"))).to have_been_made.once
      end

      it 'a pessoa conferiu e pediu para criar de novo: cria e grava na Auditoria a marca da tentativa antiga' do
        expect { expect(create!(draft.merge(recreate_unconfirmed: true))).to include(ad_id: '903') }
          .to change { Audited.audit_class.where(auditable: account, action: 'meta_ads_create_recreated', user: user).count }.by(1)
        expect(a_request(:post, meta_graph_url("#{act}/campaigns"))).to have_been_made.twice
        expect(Audited.audit_class.where(action: 'meta_ads_create_recreated').last.audited_changes)
          .to include('idempotency_key' => draft[:idempotency_key], 'mark' => 'a1b2c3d4', 'campaign_name' => campaign_name)
      end

      it 'se a Auditoria do recriar falha, não cria e a tentativa continua não confirmada' do
        allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

        expect { create!(draft.merge(recreate_unconfirmed: true)) }.to raise_error(ActiveRecord::RecordInvalid)
        expect(a_request(:post, meta_graph_url("#{act}/campaigns"))).to have_been_made.once
        expect(Crm::MetaAdsCreatedObject.last.status).to eq('unconfirmed')
      end

      describe 'o mesmo pedido com outra chave (outra aba, outro aparelho, a tela reaberta): o servidor deduplica' do
        let(:other_key) { 'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e' }
        let(:campaign_posts) { a_request(:post, meta_graph_url("#{act}/campaigns")) }

        it '(a) não cria: responde não confirmada com a chave da tentativa que já cuida do pedido' do
          expect { create!(draft.merge(idempotency_key: other_key)) }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
            expect([e.code, e.nothing_created, e.attempt_key]).to eq(['unconfirmed', false, draft[:idempotency_key]])
          }
          expect(campaign_posts).to have_been_made.once
          expect(Crm::MetaAdsCreatedObject.where(idempotency_key: other_key)).to be_empty
        end

        it '(b) pedido diferente é outra tentativa: cria' do
          expect(create!(draft.merge(idempotency_key: other_key, name: 'Outro anúncio'))).to include(ad_id: '903')
          expect(campaign_posts).to have_been_made.twice
        end

        it '(c) recriar com a chave que o servidor apontou libera, com a Auditoria' do
          attempt_key = nil
          begin
            create!(draft.merge(idempotency_key: other_key))
          rescue Crm::MetaAds::Creation::Error => e
            attempt_key = e.attempt_key
          end

          expect(create!(draft.merge(idempotency_key: attempt_key, recreate_unconfirmed: true))).to include(ad_id: '903')
          expect(campaign_posts).to have_been_made.twice
          expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_create_recreated')).to exist
        end

        it '(d) a mesma tentativa em outra conta, ou em outra conta de anúncios, não bloqueia' do
          row = Crm::MetaAdsCreatedObject.find_by!(idempotency_key: draft[:idempotency_key])
          row.update_columns(account_id: create(:account).id) # rubocop:disable Rails/SkipsModelValidations
          expect(create!(draft.merge(idempotency_key: other_key))).to include(ad_id: '903')

          row.update_columns(account_id: account.id, ad_account_id: '999999') # rubocop:disable Rails/SkipsModelValidations
          third_key = 'c3d4e5f6-a7b8-4c9d-8e0f-2a3b4c5d6e7f'
          expect(create!(draft.merge(idempotency_key: third_key))).to include(ad_id: '903')
        end

        def twin_error_for_other_key
          error = nil
          begin
            create!(draft.merge(idempotency_key: other_key))
          rescue Crm::MetaAds::Creation::Error => e
            error = e
          end
          [error&.code, error&.attempt_key]
        end

        it 'tentativa gêmea ainda criando: in_progress; parada há mais de 10 minutos: não confirmada, nunca cria sem saber' do
          row = Crm::MetaAdsCreatedObject.find_by!(idempotency_key: draft[:idempotency_key])
          row.update_columns(status: 'creating', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          expect(twin_error_for_other_key).to eq(['in_progress', draft[:idempotency_key]])

          row.update_columns(updated_at: 11.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
          expect(twin_error_for_other_key).to eq(['unconfirmed', draft[:idempotency_key]])
          expect(campaign_posts).to have_been_made.once
        end

        it 'tentativa gêmea que nem desfazer conseguiu (rollback_failed) também bloqueia: a campanha pode estar viva' do
          Crm::MetaAdsCreatedObject.find_by!(idempotency_key: draft[:idempotency_key])
                                   .update_columns(status: 'rollback_failed') # rubocop:disable Rails/SkipsModelValidations

          expect(twin_error_for_other_key).to eq(['meta_unavailable', draft[:idempotency_key]])
          expect(campaign_posts).to have_been_made.once
        end

        it 'corrida: a gêmea nasce entre a busca e o INSERT; o índice único barra e a resposta aponta para ela' do
          checks = 0
          allow_any_instance_of(Crm::MetaAds::Creation::Twin).to receive(:check!) # rubocop:disable RSpec/AnyInstance
            .and_wrap_original do |original, *args|
              checks += 1
              # A primeira busca não vê a gêmea (ela "ainda não existia"); a de depois do INSERT barrado vê.
              original.call(*args) unless checks == 1
            end

          expect(twin_error_for_other_key).to eq(['unconfirmed', draft[:idempotency_key]])
          expect(Crm::MetaAdsCreatedObject.where(idempotency_key: other_key)).to be_empty
          expect(campaign_posts).to have_been_made.once
        end

        it 'corrida no retomar: a mesma chave antiga, desfeita, não volta a criar enquanto a gêmea está viva' do
          Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: other_key, status: 'rolled_back',
                                            ad_account_id: connection.ad_account_id,
                                            request_digest: Crm::MetaAdsCreatedObject.last.request_digest)
          checks = 0
          allow_any_instance_of(Crm::MetaAds::Creation::Twin).to receive(:check!) # rubocop:disable RSpec/AnyInstance
            .and_wrap_original do |original, *args|
              checks += 1
              original.call(*args) unless checks == 1
            end

          expect(twin_error_for_other_key).to eq(['unconfirmed', draft[:idempotency_key]])
          expect(Crm::MetaAdsCreatedObject.find_by!(idempotency_key: other_key).status).to eq('rolled_back')
          expect(campaign_posts).to have_been_made.once
        end
      end

      it 'pedir para criar de novo com a campanha aparecendo na busca: desfaz a antiga antes, sem Auditoria de recriar' do
        stub_campaign_search([{ id: '950', name: campaign_name, effective_status: 'PAUSED' }])
        delete = stub_request(:delete, meta_graph_url('950')).to_return(ok(success: true))

        expect(create!(draft.merge(recreate_unconfirmed: true))).to include(ad_id: '903')
        expect(delete).to have_been_made.once
        expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_create_recreated')).to be_empty
      end
    end

    it 'recriar sem uma tentativa não confirmada desta chave é recusado, sem chamar a Meta para criar' do
      expect { create!(draft.merge(recreate_unconfirmed: true)) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_params') }
      Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: draft[:idempotency_key], status: 'rolled_back')
      expect { create!(draft.merge(recreate_unconfirmed: true)) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_params') }
      expect(a_request(:post, meta_graph_url("#{act}/campaigns"))).not_to have_been_made
    end

    it 'sem conseguir procurar: não diz que nada foi criado, e a próxima tentativa confere de novo' do
      stub_campaign_search(status: 500)

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(false) }
      expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'rollback_failed', campaign_id: nil)
    end
  end

  it 'a Meta recusou a campanha: nada criado, sem procurar' do
    stub_creation(campaign: { status: 400, body: meta_graph_error(100).to_json, headers: json })

    expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
      expect(e.code).to eq('meta_refused')
      expect(e.nothing_created).to be(true)
    }
    expect(a_request(:get, meta_graph_url("#{act}/campaigns")).with(query: hash_including({}))).not_to have_been_made
  end

  it 'a campanha foi criada mas o id não chegou a ser gravado: o desfazer usa o id que voltou' do
    stub_creation(campaign: ok(id: '950'))
    delete = stub_request(:delete, meta_graph_url('950')).to_return(ok(success: true))
    allow_any_instance_of(Crm::MetaAdsCreatedObject).to receive(:save!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      row = original.receiver
      raise ActiveRecord::StatementInvalid, 'queda do banco' if row.campaign_id_changed? && row.status == 'creating'

      original.call(*args)
    end

    expect { create! }.to raise_error(ActiveRecord::StatementInvalid)
    expect(delete).to have_been_made.once
  end

  describe 'revalida no servidor, sem chamar a Meta para criar (ponto 5)' do
    {
      'destino não confirmado' => [{ destination: 'MESSENGER' }, 'invalid_destination'],
      'lugar não confirmado para o destino' => [{ placement: 'INSTAGRAM' }, 'invalid_placement'],
      'valor por dia abaixo de R$ 6' => [{ daily_amount: '5' }, 'invalid_amount'],
      'valor por dia acima de R$ 500' => [{ daily_amount: '501' }, 'invalid_amount'],
      'valor com mais de 2 casas' => [{ daily_amount: '20.005' }, 'invalid_amount'],
      'chave que não é UUID' => [{ idempotency_key: 'a1b2c3' }, 'invalid_params'],
      'chave longa demais' => [{ idempotency_key: "#{'a' * 8}-#{'b' * 4}-#{'c' * 4}-#{'d' * 4}-#{'e' * 60}" }, 'invalid_params'],
      'início antes de hoje' => [{ start_date: '2026-10-26' }, 'invalid_dates'],
      'fim antes do início' => [{ end_date: '2026-10-27', start_date: '2026-10-28' }, 'invalid_dates'],
      'site sem https' => [{ destination: 'WEBSITE', site_url: 'http://lojaexemplo.com.br' }, 'invalid_site'],
      'número que não é da conta' => [{ whatsapp_number: '+5511999999999' }, 'invalid_whatsapp_number'],
      'Página que a pessoa não concedeu' => [{ page_id: '999' }, 'invalid_page'],
      'sem foto' => [{ media: nil }, 'invalid_media'],
      'idade invertida' => [{ age_min: 50, age_max: 30 }, 'invalid_audience'],
      'carrossel com mais de 10' => [{ cards: Array.new(10) { { kind: 'image', hash: 'x' } } }, 'invalid_media'],
      'sem chave' => [{ idempotency_key: '' }, 'invalid_params']
    }.each do |label, (changes, code)|
      it label do
        stubs = stub_creation

        expect { create!(draft.merge(changes)) }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq(code) }
        expect(stubs[:campaign]).not_to have_been_made
      end
    end
  end
end
