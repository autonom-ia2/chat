require 'rails_helper'

# Anúncio novo (#2198, Fluxo 1 e os sete pontos de "só o anúncio nasce pausado"): campanha e grupo ativos, anúncio
# PAUSED explícito, relido e pausado de novo se não vier pausado, chave de idempotência, revalidação no servidor e
# falha no meio desfazendo o começo.
RSpec.describe Crm::MetaAds::Creation::NewAd do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:act) { "act_#{connection.ad_account_id}" }
  let(:page_id) { '110000000002161' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:whatsapp_number) { '+5511900002161' }
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

  def stub_reread(effective: 'PAUSED')
    stub_request(:get, meta_graph_url('903')).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                             .to_return(ok(id: '903', account_id: connection.ad_account_id, status: effective,
                                                           effective_status: effective))
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

  it 'cria campanha e grupo ativos e o anúncio PAUSED, com destino WhatsApp e público do Brasil' do
    stubs = stub_creation
    stub_reread

    result = create!

    expect(result).to include(ad_id: '903', name: 'Bolo de pote · WhatsApp', status: 'PAUSED')
    campaign_ok = lambda do |req|
      body = form(req)
      body['objective'] == 'OUTCOME_ENGAGEMENT' && body['status'] == 'ACTIVE' && body['special_ad_categories'] == '[]' &&
        body['name'] == campaign_name
    end
    adset_ok = lambda do |req|
      body = form(req)
      targeting = JSON.parse(body['targeting'])
      body['status'] == 'ACTIVE' && body['campaign_id'] == '900' && body['daily_budget'] == '2000' &&
        body['destination_type'] == 'WHATSAPP' && body['optimization_goal'] == 'CONVERSATIONS' &&
        JSON.parse(body['promoted_object']) == { 'page_id' => page_id, 'whatsapp_phone_number' => whatsapp_number } &&
        targeting['geo_locations'] == { 'countries' => ['BR'] } && targeting['age_min'] == 25 && targeting['age_max'] == 45 &&
        targeting['publisher_platforms'] == %w[facebook instagram] && body['end_time'].nil?
    end
    creative_ok = lambda do |req|
      spec = JSON.parse(form(req)['object_story_spec'])
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
    stub_reread(effective: 'ACTIVE')
    pause = stub_request(:post, meta_graph_url('903')).with(body: { 'status' => 'PAUSED' }).to_return(ok(success: true))

    expect { create! }.to change { Audited.audit_class.where(auditable: account, action: 'meta_ads_create_repaused').count }.by(1)
    expect(pause).to have_been_made.once
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
      JSON.parse(form(req)['object_story_spec']).dig('link_data', 'call_to_action') ==
        { 'type' => 'SHOP_NOW', 'value' => { 'link' => 'https://lojaexemplo.com.br' } }
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
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(false) }
      expect(stubs[:campaign]).not_to have_been_made
      expect(Crm::MetaAdsCreatedObject.last.campaign_id).to eq('800')
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

    it 'corrida: outra linha com a mesma chave nasceu no mesmo instante → in_progress, não 500' do
      allow(Crm::MetaAdsCreatedObject).to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordInvalid.new(Crm::MetaAdsCreatedObject.new))
      stubs = stub_creation

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('in_progress') }
      expect(stubs[:campaign]).not_to have_been_made
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
    stub_reread(effective: 'ACTIVE')
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

  it 'valor com centavos vai para a Meta em centavos inteiros, sem float' do
    stubs = stub_creation
    stub_reread

    result = create!(draft.merge(daily_amount: '20.57'))

    expect(stubs[:adset].with { |req| form(req)['daily_budget'] == '2057' }).to have_been_made
    expect(result[:budget]['amount']).to eq(20.57)
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

    it 'nenhuma campanha da tentativa na Meta: nada foi criado' do
      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(true) }
      expect(a_request(:delete, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'sem conseguir procurar: não diz que nada foi criado, e a próxima tentativa confere de novo' do
      stub_campaign_search(status: 500)

      expect { create! }.to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.nothing_created).to be(false) }
      expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'rollback_failed', campaign_id: nil)
    end
  end

  it 'a campanha foi criada mas o id não chegou a ser gravado: acha pela marca e apaga' do
    stub_creation(campaign: ok(id: '950'))
    stub_campaign_search([{ id: '950', name: campaign_name, effective_status: 'ACTIVE' }])
    delete = stub_request(:delete, meta_graph_url('950')).to_return(ok(success: true))
    allow_any_instance_of(Crm::MetaAdsCreatedObject).to receive(:update!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      raise ActiveRecord::StatementInvalid, 'queda do banco' if args.first.is_a?(Hash) && args.first.key?(:campaign_id) && args.first[:campaign_id]

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
