require 'rails_helper'

# Criar post (#2198 PR 3, #2653): publica na hora na Página e/ou no Instagram, cada rede por conta própria, uma vez por
# chave de tentativa.
RSpec.describe Crm::MetaAds::Creation::Publish do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:pauses) { [] }
  let(:service) { described_class.new(connection, pause: ->(seconds) { pauses << seconds }) }
  let(:media_id) { media_signed_id('image/jpeg') }
  let(:params) do
    { idempotency_key: 'k-2653', page_id: '110', networks: %w[instagram facebook], caption: 'Promoção de novembro', media_id: media_id }
  end

  def media_signed_id(content_type)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'post', content_type: content_type)
    blob.signed_id(purpose: "meta_ads_post_media_#{account.id}", expires_in: 1.day)
  end

  def ok(body)
    { status: 200, body: body.to_json, headers: json }
  end

  def stub_permissions(*granted)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(ok(data: granted.map { |name| { permission: name, status: 'granted' } }))
  end

  def stub_pages(instagram: { id: '178', username: 'lojaexemplo' })
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(ok(data: [{ id: '110', name: 'Loja Exemplo',
                                                                            instagram_business_account: instagram }]))
  end

  def stub_facebook_photo(status: 200)
    stub_request(:get, meta_graph_url('110')).with(query: hash_including('fields' => 'access_token')).to_return(ok(access_token: 'page-token'))
    stub_request(:get, meta_graph_url('110_901')).with(query: hash_including('fields' => 'permalink_url'))
                                                 .to_return(ok(permalink_url: 'https://www.facebook.com/110/posts/901'))
    body = status == 200 ? { id: '901', post_id: '110_901' } : meta_graph_error(200)
    stub_request(:post, meta_graph_url('110/photos'))
      .with { |req| req.headers['Authorization'] == 'Bearer page-token' && form(req)['message'] == 'Promoção de novembro' }
      .to_return(status: status, body: body.to_json, headers: json)
  end

  def form(req)
    Rack::Utils.parse_nested_query(req.body)
  end

  def stub_container_status(status_code)
    stub_request(:get, meta_graph_url('c1')).with(query: hash_including('fields' => 'status_code')).to_return(ok(status_code: status_code))
  end

  def stub_instagram(status_code: 'FINISHED', publish_status: 200)
    container = stub_request(:post, meta_graph_url('178/media')).with { |req| form(req)['caption'] == 'Promoção de novembro' }
                                                                .to_return(ok(id: 'c1'))
    stub_container_status(status_code)
    body = publish_status == 200 ? { id: '1790' } : meta_graph_error(100)
    publish = stub_request(:post, meta_graph_url('178/media_publish')).with(body: hash_including('creation_id' => 'c1'))
                                                                      .to_return(status: publish_status, body: body.to_json, headers: json)
    stub_request(:get, meta_graph_url('1790')).with(query: hash_including('fields' => 'permalink'))
                                              .to_return(ok(permalink: 'https://www.instagram.com/p/abc/'))
    { container: container, publish: publish }
  end

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.example.com') { example.run } }

  before do
    stub_permissions('ads_management', 'pages_manage_ads', 'pages_manage_posts', 'instagram_content_publish')
    stub_pages
  end

  it 'publica a foto nas duas redes e devolve o que o impulsionar usa e o link de cada uma' do
    stub_facebook_photo
    instagram = stub_instagram

    expect(service.publish!(params)).to eq(
      instagram: { id: '1790', permalink: 'https://www.instagram.com/p/abc/', boostable: true },
      facebook: { id: '110_901', permalink: 'https://www.facebook.com/110/posts/901', boostable: true },
      failed: [], errors: {}, published_now: %w[instagram facebook]
    )
    expect(instagram[:container].with { |req| form(req)['image_url'].to_s.start_with?('http') })
      .to have_been_made.once
  end

  it 'a mesma chave de novo não publica outra vez: devolve o que já foi publicado' do
    stub_facebook_photo
    instagram = stub_instagram
    first = service.publish!(params)

    again = service.publish!(params)

    expect(again.except(:published_now)).to eq(first.except(:published_now))
    expect(again[:published_now]).to eq([])
    expect(instagram[:publish]).to have_been_made.once
    expect(a_request(:post, meta_graph_url('110/photos'))).to have_been_made.once
  end

  it 'falha numa rede não desfaz a outra; tentar de novo só nela publica só nela' do
    stub_facebook_photo
    stub_instagram(publish_status: 400)

    result = service.publish!(params)
    expect(result).to include(failed: ['instagram'], errors: { 'instagram' => 'meta_refused' }, published_now: ['facebook'])
    expect(result).not_to have_key(:instagram)

    stub_instagram
    retry_result = service.publish!(params.merge(networks: ['instagram']))
    expect(retry_result).to include(instagram: hash_including(id: '1790'), failed: [], published_now: ['instagram'])
    expect(a_request(:post, meta_graph_url('110/photos'))).to have_been_made.once
  end

  it 'nenhuma rede publicou: erro, com o código da Meta' do
    stub_facebook_photo(status: 400)

    expect { service.publish!(params.merge(networks: ['facebook'])) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('meta_refused') }
  end

  it 'outra tentativa publicando agora com a mesma chave: in_progress, sem chamar a Meta' do
    Crm::MetaAds::Creation::PublishState.new(account, 'k-2653', 'facebook', 'qualquer').claim!

    expect { service.publish!(params.merge(networks: ['facebook'])) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('in_progress') }
    expect(a_request(:post, meta_graph_url('110/photos'))).not_to have_been_made
  end

  it 'vídeo no Instagram que não fica pronto a tempo: processing; a próxima tentativa segue com o mesmo contêiner' do
    video = params.merge(networks: ['instagram'], media_id: media_signed_id('video/mp4'))
    first = stub_instagram(status_code: 'IN_PROGRESS')

    expect { service.publish!(video) }.to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('processing') }
    expect(first[:container].with { |req| form(req)['media_type'] == 'REELS' }).to have_been_made.once
    expect(pauses.sum).to eq(described_class::CONTAINER_WAIT['video'])

    stub_container_status('FINISHED')
    expect(service.publish!(video)).to include(instagram: hash_including(id: '1790'))
    expect(first[:container]).to have_been_made.once
  end

  it 'contêiner quebrado na Meta: recusa, e a próxima tentativa cria outro' do
    stub_instagram(status_code: 'ERROR')

    expect { service.publish!(params.merge(networks: ['instagram'])) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('meta_refused') }

    stub_instagram
    service.publish!(params.merge(networks: ['instagram']))
    expect(a_request(:post, meta_graph_url('178/media'))).to have_been_made.twice
  end

  it 'vídeo na Página: publica pelo endereço e não oferece impulsionar (a Meta devolve só o vídeo)' do
    stub_request(:get, meta_graph_url('110')).with(query: hash_including('fields' => 'access_token')).to_return(ok(access_token: 'page-token'))
    stub_request(:post, meta_graph_url('110/videos')).with(body: hash_including('description' => 'Promoção de novembro'))
                                                     .to_return(ok(id: '555'))
    stub_request(:get, meta_graph_url('555')).with(query: hash_including('fields' => 'permalink_url'))
                                             .to_return(ok(permalink_url: '/110/videos/555'))

    result = service.publish!(params.merge(networks: ['facebook'], media_id: media_signed_id('video/mp4')))

    expect(result[:facebook]).to eq(id: '555', permalink: '/110/videos/555', boostable: false)
  end

  describe 'na dúvida, nunca publica de novo sozinho' do
    it 'a Página não respondeu depois de a chamada sair: unconfirmed, e a mesma chave não chama a Meta de novo' do
      stub_facebook_photo(status: 500)

      expect { service.publish!(params.merge(networks: ['facebook'])) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('unconfirmed') }
      expect { service.publish!(params.merge(networks: ['facebook'])) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('unconfirmed') }
      expect(a_request(:post, meta_graph_url('110/photos'))).to have_been_made.once
    end

    it 'falha fora da Meta (processo, Redis) depois de a chamada sair: unconfirmed, e vai para o rastreador' do
      stub_facebook_photo
      allow(Meta::AdsGraphClient).to receive(:new).and_call_original
      allow_any_instance_of(Meta::AdsGraphClient).to receive(:publish_page_photo).and_raise(Timeout::Error) # rubocop:disable RSpec/AnyInstance
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect { service.publish!(params.merge(networks: ['facebook'])) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('unconfirmed') }
      expect(tracker).to have_received(:capture_exception)
    end

    it 'falha antes de publicar (token da Página): a chave fica livre para tentar de novo' do
      stub_request(:get, meta_graph_url('110')).with(query: hash_including('fields' => 'access_token'))
                                               .to_return(status: 500, body: '{}', headers: json)

      expect { service.publish!(params.merge(networks: ['facebook'])) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('meta_unavailable') }

      stub_facebook_photo
      expect(service.publish!(params.merge(networks: ['facebook']))).to include(facebook: hash_including(id: '110_901'))
    end

    it 'a Página respondeu sucesso sem o id do post: unconfirmed, nunca recusa (a chave fica presa)' do
      stub_request(:get, meta_graph_url('110')).with(query: hash_including('fields' => 'access_token')).to_return(ok(access_token: 'page-token'))
      stub_request(:post, meta_graph_url('110/photos')).to_return(ok({}))

      2.times do
        expect { service.publish!(params.merge(networks: ['facebook'])) }
          .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('unconfirmed') }
      end
      expect(a_request(:post, meta_graph_url('110/photos'))).to have_been_made.once
    end

    it 'contêiner do Instagram que já aparece publicado: unconfirmed, sem publicar de novo' do
      instagram = stub_instagram(status_code: 'PUBLISHED')

      expect { service.publish!(params.merge(networks: ['instagram'])) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('unconfirmed') }
      expect(instagram[:publish]).not_to have_been_made
    end

    it 'a mesma chave com outro conteúdo: idempotency_conflict, sem chamar a Meta' do
      stub_facebook_photo
      service.publish!(params.merge(networks: ['facebook']))

      expect { service.publish!(params.merge(networks: ['facebook'], caption: 'Outro texto')) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('idempotency_conflict') }
      expect(a_request(:post, meta_graph_url('110/photos'))).to have_been_made.once
    end

    it 'vídeo no Instagram não espera dentro da requisição: confere uma vez e devolve processing' do
      stub_instagram(status_code: 'IN_PROGRESS')

      expect { service.publish!(params.merge(networks: ['instagram'], media_id: media_signed_id('video/mp4'))) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('processing') }
      expect(pauses).to eq([])
    end
  end

  describe 'recusa antes de chamar a Meta' do
    it 'sem a permissão da rede: cannot_publish' do
      stub_permissions('ads_management', 'pages_manage_ads', 'pages_manage_posts')

      expect { service.publish!(params) }.to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('cannot_publish') }
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'Página que o token não alcança: invalid_page' do
      expect { service.publish!(params.merge(page_id: '999')) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('invalid_page') }
    end

    it 'Instagram sem conta ligada à Página: no_instagram' do
      stub_pages(instagram: nil)

      expect { service.publish!(params) }.to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('no_instagram') }
    end

    it 'mídia de outra conta: invalid_media' do
      other = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'post', content_type: 'image/jpeg')
                                 .signed_id(purpose: 'meta_ads_post_media_0', expires_in: 1.day)

      expect { service.publish!(params.merge(media_id: other)) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('invalid_media') }
    end

    it 'legenda acima de 2.200 caracteres, rede desconhecida ou sem chave' do
      [params.merge(caption: 'a' * 2201), params.merge(networks: ['tiktok']), params.merge(idempotency_key: '')].each do |bad|
        expect { service.publish!(bad) }.to raise_error(Crm::MetaAds::Creation::Error)
      end
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end
  end
end
