require 'rails_helper'

# Posts para impulsionar (#2198 PR 2, #2339): os da Página (token da Página, `is_eligible_for_promotion`) e os do
# Instagram ligado a ela (`boost_eligibility_info.eligible_to_boost`). Foto de perfil ou de capa da Página nunca é
# oferecida: a Meta recusa no criar (#1487472).
RSpec.describe Crm::MetaAds::Creation::Posts do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:client) { Meta::AdsGraphClient.new(access_token: connection.read_token) }
  let(:page_token) { 'token-da-pagina-2339' }
  let(:page) { { id: '110', name: 'Loja Exemplo', instagram: { id: '178', username: 'lojaexemplo' } } }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def ok(body)
    { status: 200, body: body.to_json, headers: json }
  end

  def page_post(id, eligible: true, attachment: 'photo', **extra)
    { id: "110_#{id}", message: "Post #{id}", created_time: '2026-10-20T12:00:00+0000', full_picture: "https://scontent.example/#{id}.jpg",
      is_eligible_for_promotion: eligible, attachments: { data: [{ type: attachment }] },
      reactions: { summary: { total_count: 9 } }, comments: { summary: { total_count: 2 } }, **extra }
  end

  def ig_media(id, eligible: true, media_type: 'IMAGE', info: :default)
    boost = info == :default ? { eligible_to_boost: eligible } : info
    { id: id, caption: "Legenda #{id}", timestamp: '2026-10-21T12:00:00+0000', media_type: media_type,
      media_url: "https://cdn.example/#{id}.mp4", thumbnail_url: "https://cdn.example/#{id}-capa.jpg",
      like_count: 30, comments_count: 4, boost_eligibility_info: boost }.compact
  end

  def stub_page_token(status: 200)
    body = status == 200 ? { id: '110', access_token: page_token } : meta_graph_error(10)
    stub_request(:get, meta_graph_url('110')).with(query: { fields: 'access_token' })
                                             .to_return(status: status, body: body.to_json, headers: json)
  end

  def stub_page_posts(posts, status: 200)
    body = status == 200 ? { data: posts } : meta_graph_error(1)
    stub_request(:get, meta_graph_url('110/published_posts'))
      .with(query: hash_including('fields' => Meta::AdsGraphClient::BOOST_PAGE_POST_FIELDS),
            headers: { 'Authorization' => "Bearer #{page_token}" })
      .to_return(status: status, body: body.to_json, headers: json)
  end

  def stub_ig_media(media, status: 200)
    body = status == 200 ? { data: media } : meta_graph_error(10)
    stub_request(:get, meta_graph_url('178/media'))
      .with(query: hash_including('fields' => Meta::AdsGraphClient::BOOST_INSTAGRAM_MEDIA_FIELDS),
            headers: { 'Authorization' => "Bearer #{MetaAdsHelpers::TEST_TOKEN}" })
      .to_return(status: status, body: body.to_json, headers: json)
  end

  def list
    described_class.new(client).list(page)
  end

  describe '#list' do
    before { stub_page_token }

    it 'traz os posts da Página e do Instagram no formato da tela' do
      stub_page_posts([page_post('901')])
      stub_ig_media([ig_media('1790')])

      expect(list).to eq(
        posts: [{ id: '110_901', message: 'Post 901', created_time: '2026-10-20T12:00:00Z',
                  image_url: 'https://scontent.example/901.jpg', reactions: 9, comments: 2, eligible: true, reason: nil }],
        instagram_posts: [{ id: '1790', caption: 'Legenda 1790', timestamp: '2026-10-21T12:00:00Z',
                            image_url: 'https://cdn.example/1790.mp4', likes: 30, comments: 4, eligible: true, reason: nil }],
        posts_error: nil
      )
    end

    it 'foto de capa e foto de perfil da Página aparecem não elegíveis, com o motivo, mesmo com a Meta dizendo que pode' do
      stub_page_posts([page_post('902', attachment: 'cover_photo'), page_post('903', attachment: 'profile_media')])
      stub_ig_media([])

      expect(list[:posts].map { |post| post.slice(:id, :eligible, :reason) }).to eq(
        [{ id: '110_902', eligible: false, reason: 'profile_or_cover' }, { id: '110_903', eligible: false, reason: 'profile_or_cover' }]
      )
    end

    it 'post da Página que a Meta não deixa promover fica não elegível, sem motivo (a Meta não diz)' do
      stub_page_posts([page_post('904', eligible: false), page_post('905', eligible: nil)])
      stub_ig_media([])

      expect(list[:posts].map { |post| post.slice(:eligible, :reason) }).to all(eq(eligible: false, reason: nil))
    end

    it 'mídia do Instagram só é elegível com eligible_to_boost true; vídeo mostra a capa' do
      stub_page_posts([])
      stub_ig_media([ig_media('1791', eligible: false), ig_media('1792', info: nil), ig_media('1793', media_type: 'VIDEO')])

      posts = list[:instagram_posts]

      expect(posts.map { |post| post.slice(:id, :eligible) }).to eq(
        [{ id: '1791', eligible: false }, { id: '1792', eligible: false }, { id: '1793', eligible: true }]
      )
      expect(posts.last[:image_url]).to eq('https://cdn.example/1793-capa.jpg')
    end

    it 'carrossel sem media_url usa a imagem do primeiro filho' do
      stub_page_posts([])
      child = { media_type: 'IMAGE', media_url: 'https://cdn.example/filho.jpg' }
      album = ig_media('1794', media_type: 'CAROUSEL_ALBUM').except(:media_url, :thumbnail_url).merge(children: { data: [child] })
      stub_ig_media([album])

      expect(list[:instagram_posts].first[:image_url]).to eq('https://cdn.example/filho.jpg')
    end

    it 'sem Instagram ligado à Página: não lê mídia' do
      stub_page_posts([])

      result = described_class.new(client).list(page.merge(instagram: nil))

      expect(result).to include(instagram_posts: [], posts_error: nil)
      expect(a_request(:get, meta_graph_url('178/media'))).not_to have_been_made
    end

    it 'falha ao ler os posts: listas vazias com o erro, para a tela dizer que não conseguiu ler (nunca "sem posts")' do
      stub_page_posts([], status: 500)
      stub_ig_media([], status: 403)

      expect(list).to eq(posts: [], instagram_posts: [], posts_error: 'posts_unreadable')
    end

    it 'sem token da Página: posts da Página vazios com o erro, e o Instagram segue' do
      stub_page_token(status: 403)
      stub_ig_media([ig_media('1790')])

      expect(list).to include(posts: [], posts_error: 'posts_unreadable')
      expect(list[:instagram_posts].size).to eq(1)
    end
  end

  describe '#find!' do
    before do
      stub_page_token
      stub_page_posts([page_post('901'), page_post('902', attachment: 'cover_photo')])
      stub_ig_media([ig_media('1790'), ig_media('1791', eligible: false)])
    end

    it 'devolve o post escolhido, relido na hora' do
      expect(described_class.new(client).find!(page, 'instagram', '1790')).to include(id: '1790', eligible: true)
      expect(described_class.new(client).find!(page, 'facebook', '110_901')).to include(id: '110_901', eligible: true)
    end

    it 'post que não é desta Página ou deste Instagram: invalid_post' do
      expect { described_class.new(client).find!(page, 'facebook', '999_1') }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_post') }
      expect { described_class.new(client).find!(page, 'tiktok', '1790') }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_post') }
    end

    it 'post não elegível (inclusive capa): post_not_eligible' do
      %w[facebook:110_902 instagram:1791].each do |pair|
        source, id = pair.split(':')
        expect { described_class.new(client).find!(page, source, id) }
          .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('post_not_eligible') }
      end
    end

    it 'sem conseguir reler os posts: erro da Meta, sem criar nada' do
      stub_page_posts([], status: 500)

      expect { described_class.new(client).find!(page, 'facebook', '110_901') }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_unavailable') }
    end
  end
end
