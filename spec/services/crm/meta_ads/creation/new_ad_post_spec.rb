require 'rails_helper'

# Impulsionar post (#2198 PR 2, #2339): o mesmo criar do anúncio novo (três níveis PAUSED, releitura, chave de
# idempotência, desfazer), com o criativo apontando para um post que já existe.
# - Instagram: `object_id` (a Página), `instagram_user_id` e `source_instagram_media_id`; com número na conta, botão de
#   WhatsApp e o grupo de conversas no WhatsApp. Sem número, engajamento no próprio post.
# - Página: `object_story_id`, só no Facebook, sem WhatsApp (botão em post da Página não está confirmado).
RSpec.describe Crm::MetaAds::Creation::NewAd do
  # Chaves da tentativa no formato que a tela gera (UUID).
  let(:key) { %w[b2c3d4e5 2339 4000 8000 000000002339].join('-') }
  let(:other_key) { %w[c3d4e5f6 2339 4000 8000 000000002339].join('-') }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:act) { "act_#{connection.ad_account_id}" }
  let(:page_id) { '110000000002161' }
  let(:page_post_id) { "#{page_id}_901" }
  let(:page_token) { 'token-da-pagina-2339' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:whatsapp_number) { '+5511900002161' }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  let(:draft) do
    {
      kind: 'post', idempotency_key: key, name: 'Vestidos de verão · Impulsionar',
      page_id: page_id, post_source: 'instagram', post_id: '1790', whatsapp_number: whatsapp_number,
      region: 'BR', states: [], age_min: 25, age_max: 45, special_category: false,
      daily_amount: '6', start_date: '2026-10-28', end_date: '2026-10-29'
    }
  end

  def ok(body)
    { status: 200, body: body.to_json, headers: json }
  end

  def form(request_signature)
    Rack::Utils.parse_nested_query(request_signature.body)
  end

  def stub_creation
    {
      campaign: stub_request(:post, meta_graph_url("#{act}/campaigns")).to_return(ok(id: '900')),
      adset: stub_request(:post, meta_graph_url("#{act}/adsets")).to_return(ok(id: '901')),
      creative: stub_request(:post, meta_graph_url("#{act}/adcreatives")).to_return(ok(id: '902')),
      ad: stub_request(:post, meta_graph_url("#{act}/ads")).to_return(ok(id: '903'))
    }
  end

  def stub_reread
    %w[900 901 903].each do |id|
      stub_request(:get, meta_graph_url(id)).with(query: { fields: Meta::AdsGraphClient::OBJECT_STATUS_FIELDS })
                                            .to_return(ok(id: id, status: 'PAUSED', effective_status: 'PAUSED'))
    end
  end

  def stub_posts(page_posts: [{ id: page_post_id, is_eligible_for_promotion: true, attachments: { data: [{ type: 'photo' }] } }],
                 media: [{ id: '1790', boost_eligibility_info: { eligible_to_boost: true } }])
    stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token' }).to_return(ok(id: page_id, access_token: page_token))
    stub_request(:get, meta_graph_url("#{page_id}/published_posts")).with(query: hash_including({})).to_return(ok(data: page_posts))
    stub_request(:get, meta_graph_url('178/media')).with(query: hash_including({})).to_return(ok(data: media))
  end

  def create!(params = draft)
    described_class.new(connection, user: user).create!(params)
  end

  def digest_of(params)
    Crm::MetaAds::Creation::PostDraft.new(params, account: account, zone: zone).validate!.digest
  end

  before do
    travel_to Time.zone.parse('2026-10-28 12:00:00 -0300')
    create(:channel_whatsapp, account: account, phone_number: whatsapp_number, validate_provider_config: false, sync_templates: false)
    page = { id: page_id, name: 'Loja Exemplo', instagram_business_account: { id: '178', username: 'lojaexemplo' } }
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including('fields' => Meta::AdsGraphClient::PAGES_FIELDS))
                                                     .to_return(ok(data: [page]))
    stub_request(:get, meta_graph_url(act)).with(query: hash_including({})).to_return(ok(id: act, currency: 'BRL'))
    stub_request(:get, meta_graph_url("#{act}/campaigns")).with(query: hash_including({})).to_return(ok(data: []))
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(ok(data: %w[ads_management pages_manage_ads].map { |name| { permission: name, status: 'granted' } }))
    stub_posts
  end

  it 'post do Instagram com número: três níveis PAUSED, conversas no WhatsApp e o criativo apontando para o post' do
    stubs = stub_creation
    stub_reread

    expect(create!).to include(ad_id: '903', status: 'PAUSED')

    adset_ok = lambda do |req|
      body = form(req)
      body['status'] == 'PAUSED' && body['daily_budget'] == '600' && body['destination_type'] == 'WHATSAPP' &&
        body['optimization_goal'] == 'CONVERSATIONS' &&
        JSON.parse(body['promoted_object']) == { 'page_id' => page_id, 'whatsapp_phone_number' => whatsapp_number } &&
        JSON.parse(body['targeting'])['publisher_platforms'] == %w[facebook instagram]
    end
    creative_ok = lambda do |req|
      body = form(req)
      body['object_id'] == page_id && body['instagram_user_id'] == '178' && body['source_instagram_media_id'] == '1790' &&
        JSON.parse(body['call_to_action']) == { 'type' => 'WHATSAPP_MESSAGE', 'value' => { 'app_destination' => 'WHATSAPP' } } &&
        body['object_story_spec'].nil? && body['object_story_id'].nil? && body['url_tags'].nil?
    end
    expect(stubs[:campaign].with { |req| form(req).values_at('objective', 'status') == %w[OUTCOME_ENGAGEMENT PAUSED] })
      .to have_been_made.once
    expect(stubs[:adset].with(&adset_ok)).to have_been_made.once
    expect(stubs[:creative].with(&creative_ok)).to have_been_made.once
    expect(stubs[:ad].with { |req| form(req)['status'] == 'PAUSED' }).to have_been_made.once
    expect(Crm::MetaAdsCreatedObject.last).to have_attributes(status: 'created', ad_id: '903')
  end

  it 'post da Página: object_story_id, só no Facebook, engajamento no post e sem WhatsApp' do
    stubs = stub_creation
    stub_reread

    create!(draft.merge(post_source: 'facebook', post_id: page_post_id))

    adset_ok = lambda do |req|
      body = form(req)
      body['destination_type'] == 'ON_POST' && body['optimization_goal'] == 'POST_ENGAGEMENT' && body['promoted_object'].nil? &&
        JSON.parse(body['targeting'])['publisher_platforms'] == ['facebook']
    end
    creative_ok = lambda do |req|
      body = form(req)
      body['object_story_id'] == page_post_id && body['call_to_action'].nil? && body['source_instagram_media_id'].nil? &&
        body['url_tags'].nil?
    end
    expect(stubs[:adset].with(&adset_ok)).to have_been_made.once
    expect(stubs[:creative].with(&creative_ok)).to have_been_made.once
  end

  it 'post do Instagram numa conta sem número: engajamento no post, sem botão' do
    account.inboxes.destroy_all
    stubs = stub_creation
    stub_reread

    create!(draft.merge(whatsapp_number: nil))

    expect(stubs[:adset].with { |req| form(req).values_at('destination_type', 'optimization_goal') == %w[ON_POST POST_ENGAGEMENT] })
      .to have_been_made.once
    expect(stubs[:creative].with { |req| form(req)['call_to_action'].nil? }).to have_been_made.once
  end

  it 'post do Instagram com número na conta exige escolher o número' do
    stubs = stub_creation

    expect { create!(draft.merge(whatsapp_number: nil)) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_whatsapp_number') }
    expect(stubs[:campaign]).not_to have_been_made
  end

  it 'post que não está na Página nem no Instagram da conexão: recusa antes de criar qualquer coisa' do
    stubs = stub_creation

    expect { create!(draft.merge(post_id: '999')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_post') }
    expect(stubs[:campaign]).not_to have_been_made
    expect(Crm::MetaAdsCreatedObject.count).to eq(0)
  end

  it 'foto de capa da Página: recusa antes de criar, mesmo com a Meta dizendo que pode promover' do
    stub_posts(page_posts: [{ id: page_post_id, is_eligible_for_promotion: true, attachments: { data: [{ type: 'cover_photo' }] } }])
    stubs = stub_creation

    expect { create!(draft.merge(post_source: 'facebook', post_id: page_post_id)) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('post_not_eligible') }
    expect(stubs[:campaign]).not_to have_been_made
  end

  it 'recusa antes de gravar com tentativa não confirmada da mesma chave: não diz "nada foi criado"' do
    Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: key, status: 'unconfirmed', name: 'Antes',
                                      ad_account_id: connection.ad_account_id)
    stub_posts(media: [{ id: '1790', boost_eligibility_info: { eligible_to_boost: false } }])
    stubs = stub_creation

    expect { create!(draft.merge(recreate_unconfirmed: true)) }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
      expect(e.code).to eq('post_not_eligible')
      expect(e.nothing_created).to be(false)
      expect(e.attempt_key).to eq(key)
    }
    expect(stubs[:campaign]).not_to have_been_made
  end

  it 'origem desconhecida ou sem post: invalid_post' do
    expect { create!(draft.merge(post_source: 'tiktok')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_post') }
    expect { create!(draft.merge(post_id: '')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_post') }
  end

  it 'a mesma chave não cria dois anúncios' do
    stubs = stub_creation
    stub_reread

    first = create!
    again = create!

    expect(again).to eq(first)
    expect(stubs[:campaign]).to have_been_made.once
  end

  # O gêmeo (mesmo pedido com outra chave enquanto o primeiro não terminou) é do PR 1 (Attempt); aqui, só que o post
  # entra no pedido.
  it 'outro post ou outra origem é outro pedido; outra chave, o mesmo' do
    expect(digest_of(draft)).not_to eq(digest_of(draft.merge(post_id: '1791')))
    expect(digest_of(draft)).not_to eq(digest_of(draft.merge(post_source: 'facebook', post_id: page_post_id)))
    expect(digest_of(draft)).to eq(digest_of(draft.merge(idempotency_key: other_key)))
  end
end
