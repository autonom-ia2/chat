require 'rails_helper'

# Seus posts (#2302, F1 #2304): os perfis da conta, os números do perfil escolhido (os da aba de Anúncios, testados em
# spec/services/crm/meta_ads/organico/tela_spec.rb, aqui substituídos) e os posts com os números de cada um, lidos numa
# chamada por página de posts (formatos da chamada real de 27/10, v23).
RSpec.describe SeusPosts::Leitura do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agora) { Time.zone.parse('2026-10-27 12:00:00') }
  let(:fb) { 'https://graph.facebook.com/v23.0' }
  let(:ig) { 'https://graph.instagram.com/v23.0' }

  around do |example|
    travel_to(agora) { example.run }
  end

  before do
    Rails.cache.clear
    Current.account = account
  end

  after { Current.reset }

  def leitura(days: 30, perfil: nil, user: admin)
    Current.user = user
    viewer = { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
    described_class.new(account: account, perfil: perfil, days: days, viewer: viewer).perform
  end

  def numeros_ok(klass, extra = {})
    allow(klass).to receive(:new).and_return(instance_double(klass, perform: { status: 'ok', followers: 10, **extra }))
  end

  def json(data)
    { status: 200, body: { data: data }.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def insights(numeros, period = 'lifetime')
    { 'data' => numeros.map { |nome, valor| { 'name' => nome, 'period' => period, 'values' => [{ 'value' => valor }] } } }
  end

  def dias_atras(dias)
    (agora - dias.days).iso8601
  end

  # A chamada pelos campos pedidos (as constantes do cliente: :INSTAGRAM, :PAGE, :PAGE_VIEWS).
  def com_campos(nome)
    { query: hash_including('fields' => Meta::AdsGraphClient::SeusPosts.const_get("SEUS_POSTS_#{nome}_FIELDS")) }
  end

  describe 'Instagram' do
    # A factory do Instagram já cria a caixa nesta conta.
    let!(:canal) { create(:channel_instagram, account: account) }

    before do
      numeros_ok(SeusPosts::NumerosInstagram, username: 'studioacme')
      midias = [
        { 'id' => 'm1', 'caption' => 'Cozinha nova', 'timestamp' => dias_atras(2), 'media_type' => 'IMAGE', 'media_url' => 'https://img/1',
          'insights' => insights('views' => 900, 'reach' => 700, 'likes' => 90, 'comments' => 9, 'saved' => 5, 'shares' => 2) },
        { 'id' => 'm2', 'caption' => 'Reels', 'timestamp' => dias_atras(40), 'media_type' => 'VIDEO', 'thumbnail_url' => 'https://img/2',
          'insights' => insights('views' => 300, 'reach' => 200, 'likes' => 30, 'comments' => 3) },
        # Post dentro de álbum ou sem insights: sem número, fora da média.
        { 'id' => 'm3', 'caption' => 'Sem números', 'timestamp' => dias_atras(5), 'media_type' => 'CAROUSEL_ALBUM', 'media_url' => 'https://img/3' },
        # Post de hoje que ainda não apareceu: zero real, fora da média.
        { 'id' => 'm4', 'caption' => 'Agora', 'timestamp' => dias_atras(0.1), 'media_type' => 'IMAGE', 'media_url' => 'https://img/4',
          'insights' => insights('views' => 0, 'likes' => 0, 'comments' => 0) }
      ]
      stub_request(:get, "#{ig}/me/media").with(query: hash_including({})).to_return(json(midias))
    end

    it 'traz só os posts do período, com os números de cada um' do
      perfil = leitura(days: 30)[:perfil]

      expect(perfil).to include(id: "instagram-#{canal.id}", network: 'instagram', status: 'ok', posts_status: 'ok')
      expect(perfil[:posts].pluck(:id)).to eq(%w[m4 m1 m3])
      expect(perfil[:posts].second).to include(type: 'foto', image_url: 'https://img/1', views: 900, likes: 90, comments: 9, saved: 5,
                                               boosted: nil)
      expect(perfil[:posts].last).to include(type: 'carrossel', views: nil, likes: nil)
      expect(perfil).to include(posts_truncated: false, posts_stale: false)
    end

    it 'o normal não muda com o período e ignora o post sem número e o zero' do
      normal30 = leitura(days: 30)[:perfil][:normal]
      normal7 = leitura(days: 7)[:perfil][:normal]

      expect(normal30).to eq(views: 600, likes: 60, comments: 6)
      expect(normal7).to eq(normal30)
    end

    it 'guarda o nome do perfil para a escolha no topo' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      leitura

      expect(leitura[:perfis]).to eq([{ id: "instagram-#{canal.id}", network: 'instagram', name: '@studioacme' }])
    end

    it 'pede os números de cada post na mesma chamada da lista' do
      leitura

      expect(a_request(:get, "#{ig}/me/media").with(**com_campos(:INSTAGRAM))).to have_been_made.once
    end

    it 'a lista dos 90 dias é lida uma vez para 7, 30 e 90 dias' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      [7, 30, 90].each { |dias| leitura(days: dias) }

      expect(a_request(:get, "#{ig}/me/media").with(query: hash_including({}))).to have_been_made.once
    end

    it 'lista que parou no teto de posts lidos sai marcada' do
      corpo = { data: [], paging: { cursors: { after: 'x' }, next: "#{ig}/me/media?after=x" } }.to_json
      resposta = { status: 200, body: corpo, headers: { 'Content-Type' => 'application/json' } }
      stub_request(:get, "#{ig}/me/media").with(query: hash_including({})).to_return(resposta)

      expect(leitura[:perfil]).to include(posts_status: 'ok', posts_truncated: true)
    end

    it 'Meta fora só nos posts: os números ficam e os posts vêm indisponíveis' do
      stub_request(:get, "#{ig}/me/media").with(query: hash_including({})).to_return(status: 500, body: '{}')

      perfil = leitura[:perfil]
      expect(perfil).to include(status: 'ok', username: 'studioacme', posts_status: 'unavailable', posts: [], normal: nil)
    end

    it 'Meta fora depois de uma leitura boa: serve a última, marcada' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      leitura
      travel 20.minutes
      allow(SeusPosts::NumerosInstagram).to receive(:new).and_raise(Crm::MetaAds::Organico::Indisponivel.new('fora', codigo: 4))
      stub_request(:get, "#{ig}/me/media").with(query: hash_including({})).to_return(status: 500, body: '{}')

      perfil = leitura[:perfil]
      expect(perfil).to include(status: 'ok', stale: true, posts_status: 'ok', posts_stale: true)
      expect(perfil[:posts].pluck(:id)).to eq(%w[m4 m1 m3])
    end

    it 'Meta limitando com cópia antiga: serve a cópia e espera antes de chamar a Meta de novo' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      leitura
      travel 20.minutes
      stub_request(:get, "#{ig}/me/media")
        .with(query: hash_including({}))
        .to_return(status: 400, body: { error: { code: 4, message: 'limite' } }.to_json)

      2.times { expect(leitura[:perfil]).to include(posts_status: 'ok', posts_stale: true) }
      # Uma da leitura boa e uma da falha: a segunda recarga não volta à Meta.
      expect(a_request(:get, "#{ig}/me/media").with(query: hash_including({}))).to have_been_made.twice
    end

    it 'números e posts do perfil dividem o mesmo teto de tempo' do
      prazos = []
      allow(SeusPosts::NumerosInstagram).to receive(:new) do |**args|
        prazos << args[:prazo]
        instance_double(SeusPosts::NumerosInstagram, perform: { status: 'ok', followers: 10 })
      end
      allow(SeusPosts::Posts).to receive(:para).and_wrap_original do |original, *args, **opcoes|
        prazos << opcoes[:prazo]
        original.call(*args, **opcoes)
      end

      leitura

      expect(prazos.size).to eq(2)
      expect(prazos.uniq.size).to eq(1)
      expect(prazos.first).to be_a(Float)
    end

    it 'teto de tempo de verdade nos posts: indisponível, sem a espera de falha da Meta' do
      store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(store)
      stub_const('SeusPosts::Orcamento::SEGUNDOS', 0)

      expect(leitura[:perfil]).to include(status: 'ok', posts_status: 'unavailable')
      expect(store.exist?("seus_posts:v2:#{account.id}:posts:instagram-#{canal.id}:falha")).to be(false)
      expect(a_request(:get, "#{ig}/me/media").with(query: hash_including({}))).not_to have_been_made
    end

    it 'o nosso teto de tempo não é falha da Meta: a próxima recarga lê de novo' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      leitura
      travel 20.minutes
      posts = instance_double(SeusPosts::PostsInstagram)
      allow(posts).to receive(:perform).and_raise(Crm::MetaAds::Organico::Indisponivel.new('passou do tempo', codigo: 'tempo'))
      allow(SeusPosts::Posts).to receive(:para).and_return(posts)

      2.times { expect(leitura[:perfil]).to include(posts_status: 'ok', posts_stale: true) }
      expect(posts).to have_received(:perform).twice
    end
  end

  describe 'Página' do
    let(:canal) do
      stub_request(:post, 'https://graph.facebook.com/v3.2/me/subscribed_apps')
      create(:channel_facebook_page, account: account, page_id: '1001', inbox: nil)
    end

    def vistas(sem, com)
      lados = [{ 'is_from_ads' => '0', 'value' => sem }]
      lados << { 'is_from_ads' => '1', 'value' => com } if com
      { 'data' => [{ 'name' => 'post_media_view', 'period' => 'lifetime', 'values' => lados }] }
    end

    # Formato real: post_total_media_view_unique vem duas vezes, lifetime e day.
    def resto(pessoas, cliques)
      { 'data' => insights('post_total_media_view_unique' => pessoas, 'post_clicks' => cliques)['data'] +
        insights('post_total_media_view_unique' => 1)['data'].map { |item| item.merge('period' => 'day') } }
    end

    # numeros: [curtidas, comentarios, pessoas, cliques]
    def post_da_pagina(id, dias, numeros)
      curtidas, comentarios, pessoas, cliques = numeros
      { 'id' => id, 'message' => "Post #{id}", 'created_time' => dias_atras(dias), 'full_picture' => "https://img/#{id}",
        'reactions' => { 'summary' => { 'total_count' => curtidas } }, 'comments' => { 'summary' => { 'total_count' => comentarios } },
        'insights' => resto(pessoas, cliques) }
    end

    before do
      create(:inbox, account: account, channel: canal)
      numeros_ok(SeusPosts::NumerosPagina, name: 'Studio Acme')
      lista = [post_da_pagina('p1', 3, [40, 4, 500, 20]), post_da_pagina('p2', 10, [60, 6, 700, 30]),
               post_da_pagina('p3', 12, [900, 90, 9000, 300])]
      vistas_dos_posts = [{ 'id' => 'p1', 'insights' => vistas(800, nil) }, { 'id' => 'p2', 'insights' => vistas(1000, 0) },
                          { 'id' => 'p3', 'insights' => vistas(2000, 15_000) }]
      stub_request(:get, "#{fb}/1001/published_posts").with(**com_campos(:PAGE_VIEWS)).to_return(json(vistas_dos_posts))
      stub_request(:get, "#{fb}/1001/published_posts").with(**com_campos(:PAGE)).to_return(json(lista))
    end

    it 'separa as vezes sem anúncio e usa as pessoas da vida toda do post' do
      p1 = leitura[:perfil][:posts].find { |item| item[:id] == 'p1' }

      expect(p1).to include(views: 800, views_from_ads: nil, reach: 500, clicks: 20, likes: 40, comments: 4)
    end

    it 'compartilhamentos vêm do post; sem o campo (ninguém compartilhou), 0' do
      lista = [post_da_pagina('p1', 3, [40, 4, 500, 20]).merge('shares' => { 'count' => 7 }), post_da_pagina('p2', 10, [60, 6, 700, 30])]
      stub_request(:get, "#{fb}/1001/published_posts").with(**com_campos(:PAGE)).to_return(json(lista))
      posts = leitura[:perfil][:posts].to_h { |item| [item[:id], item[:shares]] }

      expect(posts).to include('p1' => 7, 'p2' => 0)
    end

    it 'sem o lado de anúncio não se sabe se teve anúncio (nil); com o lado em 0, não teve' do
      posts = leitura[:perfil][:posts]

      expect(posts.find { |item| item[:id] == 'p1' }).to include(boosted: nil)
      expect(posts.find { |item| item[:id] == 'p2' }).to include(boosted: false, views_from_ads: 0)
    end

    it 'post sem o recorte de anúncio: não se sabe se teve anúncio, entra no normal sem as vezes' do
      stub_request(:get, "#{fb}/1001/published_posts").with(**com_campos(:PAGE_VIEWS)).to_return(json([]))

      perfil = leitura[:perfil]

      expect(perfil[:posts].pluck(:boosted)).to eq([nil, nil, nil])
      expect(perfil[:normal]).to eq(views: nil, reach: 3400, likes: 333, comments: 33, clicks: 117)
    end

    it 'Página com Instagram ligado (instagram_id preenchido) continua na lista de perfis' do
      canal.update!(instagram_id: '178400')

      expect(leitura[:perfis].pluck(:id)).to eq(["facebook-#{canal.id}"])
    end

    it 'o post impulsionado fica fora do normal' do
      perfil = leitura[:perfil]

      expect(perfil[:posts].find { |item| item[:id] == 'p3' }).to include(boosted: true, views: 2000, views_from_ads: 15_000)
      expect(perfil[:normal]).to eq(views: 900, reach: 600, likes: 50, comments: 5, clicks: 25)
    end
  end

  it 'Meta fora no perfil escolhido: só ele fica indisponível' do
    canal = create(:channel_instagram, account: account)
    allow(SeusPosts::NumerosInstagram).to receive(:new).and_raise(Crm::MetaAds::Organico::Indisponivel.new('fora', codigo: 2))

    expect(leitura[:perfil]).to eq(id: "instagram-#{canal.id}", network: 'instagram', inbox_id: canal.inbox.id, status: 'unavailable')
  end
end
