require 'rails_helper'

# Seus posts (#2199): os números orgânicos da Página (read_insights) e do Instagram (instagram_business_manage_insights)
# lidos da Meta, no formato que a tela já usa. Sem caixa: not_connected. Meta recusando por permissão ou token:
# needs_permission. Meta fora do ar: Indisponivel (a tela mostra "Tentar de novo").
RSpec.describe Crm::MetaAds::Organico::Tela do
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

  # Quem abre a tela (pundit_user do controller); o administrador vê todas as caixas.
  def tela(days:, user: admin)
    Current.user = user
    viewer = { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
    described_class.new(account: account, days: days, viewer: viewer)
  end

  # Dias de calendário contando hoje (fuso da conta: UTC no teste).
  def janela(dias, anterior: false)
    inicio = (agora.to_date - (dias - 1)).in_time_zone
    return { since: (inicio - dias.days).to_i.to_s, until: inicio.to_i.to_s } if anterior

    { since: inicio.to_i.to_s, until: agora.to_i.to_s }
  end

  def total(name, value, breakdown: nil)
    entry = { 'name' => name, 'period' => 'day', 'total_value' => { 'value' => value } }
    entry['total_value']['breakdowns'] = [breakdown] if breakdown
    entry
  end

  def recorte(chave, valores)
    { 'dimension_keys' => [chave], 'results' => valores.map { |nome, valor| { 'dimension_values' => [nome], 'value' => valor } } }
  end

  def diario(name, valores)
    { 'name' => name, 'period' => 'day', 'values' => valores.map { |valor| { 'value' => valor } } }
  end

  # Formato real (chamada de 27/10): sem total_value, um valor por dia para cada lado do recorte ("0" e "1").
  def por_anuncio(name, views, ads)
    organico = views - ads
    dias = [[organico / 2, ads / 2], [organico - (organico / 2), ads - (ads / 2)]]
    values = dias.flat_map { |sem, com| [{ 'value' => sem, 'is_from_ads' => '0' }, { 'value' => com, 'is_from_ads' => '1' }] }
    { 'name' => name, 'period' => 'day', 'values' => values }
  end

  def json(body = nil, status: 200, **campos)
    { status: status, body: (body || campos).to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_get(url, query, data)
    stub_request(:get, url).with(query: hash_including(query)).to_return(json(data: data))
  end

  def erro(code, status: 400)
    json({ error: { code: code, message: 'Meta recusou' } }, status: status)
  end

  describe 'Página' do
    # A factory da Página cria a caixa noutra conta; aqui a caixa é desta conta.
    let(:channel) do
      stub_request(:post, 'https://graph.facebook.com/v3.2/me/subscribed_apps')
      create(:channel_facebook_page, account: account, page_id: '1001', inbox: nil)
    end
    let!(:inbox) { create(:inbox, account: account, channel: channel, name: 'Studio Acme') }

    def stub_pagina_janela(dias, anterior:, numeros:)
      query = janela(dias, anterior: anterior)
      insights = "#{fb}/1001/insights"
      stub_get(insights, query.merge(metric: 'page_total_media_view_unique', period: 'total_over_range'),
               [diario('page_total_media_view_unique', [numeros[:reach]])])
      stub_get(insights, query.merge(metric: 'page_media_view', breakdown: 'is_from_ads'),
               [por_anuncio('page_media_view', numeros[:views], numeros[:ads])])
      stub_get(insights, query.merge(metric: 'page_post_engagements,page_daily_follows_unique', period: 'day'),
               [diario('page_post_engagements', numeros[:engajamento]), diario('page_daily_follows_unique', numeros[:seguidores])])
    end

    def posts_da_pagina
      [
        { id: 'p2', message: 'Bastidores', created_time: '2026-10-18T10:00:00+0000', permalink_url: 'https://fb.com/p2',
          full_picture: 'https://img/p2.jpg', reactions: { summary: { total_count: 100 } }, comments: { summary: { total_count: 21 } },
          insights: { data: [diario('post_total_media_view_unique', [1290])] } },
        { id: 'p1', message: 'Agenda aberta', created_time: '2026-10-24T10:00:00+0000', permalink_url: 'https://fb.com/p1',
          full_picture: 'https://img/p1.jpg', shares: { count: 6 }, reactions: { summary: { total_count: 150 } },
          comments: { summary: { total_count: 30 } }, insights: { data: [diario('post_total_media_view_unique', [1840])] } },
        { id: 'p3', created_time: '2026-10-10T10:00:00+0000', permalink_url: 'https://fb.com/p3',
          reactions: { summary: { total_count: 2 } }, comments: { summary: { total_count: 0 } }, insights: { data: [] } },
        { id: 'p4', message: 'Pouco', created_time: '2026-10-05T10:00:00+0000', permalink_url: 'https://fb.com/p4',
          reactions: { summary: { total_count: 1 } }, comments: { summary: { total_count: 0 } }, insights: { data: [] } }
      ]
    end

    def stub_pagina(dias: 30)
      stub_request(:get, "#{fb}/1001")
        .with(query: hash_including(fields: 'name,link,followers_count'))
        .to_return(json(name: 'Studio Acme', link: 'https://www.facebook.com/studioacme', followers_count: 8412))
      stub_pagina_janela(dias, anterior: false,
                               numeros: { reach: 4900, views: 12_700, ads: 4064, engajamento: [300, 491], seguidores: [100, 46] })
      stub_pagina_janela(dias, anterior: true,
                               numeros: { reach: 4100, views: 11_000, ads: 3000, engajamento: [400, 300], seguidores: [60, 42] })
      stub_get("#{fb}/1001/published_posts", janela(dias), posts_da_pagina)
    end

    it 'devolve os números da Página com o período anterior, a parte de anúncios e os 3 posts com mais curtidas' do
      stub_pagina
      create_list(:conversation, 2, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, created_at: 40.days.ago)

      page = tela(days: 30).perform[:page]

      expect(page).to include(status: 'ok', name: 'Studio Acme', link: 'https://www.facebook.com/studioacme', followers: 8412,
                              reach: 4900, views: 12_700, views_from_ads: 4064, interactions: 791, new_followers: 146)
      expect(page[:previous]).to eq(reach: 4100, views: 11_000, interactions: 700, new_followers: 102)
      expect(page[:messages]).to eq(count: 2, inbox_id: inbox.id)
      expect(page[:top_posts].pluck(:id)).to eq(%w[p1 p2 p3])
      expect(page[:top_posts].first).to eq(id: 'p1', text: 'Agenda aberta', image_url: 'https://img/p1.jpg', reach: 1840,
                                           interactions: 186, created_time: '2026-10-24T10:00:00+0000', permalink: 'https://fb.com/p1')
      expect(page[:top_posts].last).to include(text: '', reach: 0, image_url: nil)
    end

    it 'pede de novo o acesso quando a Meta recusa por falta de permissão' do
      stub_request(:get, "#{fb}/1001").with(query: hash_including({})).to_return(json(name: 'Studio Acme', followers_count: 1))
      stub_request(:get, "#{fb}/1001/insights").with(query: hash_including({})).to_return(erro(10, status: 403))

      page = tela(days: 7).perform[:page]

      expect(page).to eq(status: 'needs_permission', name: 'Studio Acme', inbox_id: inbox.id)
    end

    it 'quem não vê a caixa nem pode reautorizá-la não recebe o nome nem o id da caixa' do
      stub_request(:get, "#{fb}/1001").with(query: hash_including({})).to_return(json(name: 'Studio Acme', followers_count: 1))
      stub_request(:get, "#{fb}/1001/insights").with(query: hash_including({})).to_return(erro(10, status: 403))
      agente = create(:user, account: account, role: :agent)

      page = tela(days: 7, user: agente).perform[:page]

      expect(page).to eq(status: 'needs_permission', inbox_id: nil)
    end

    it 'quem não vê a caixa recebe a contagem nula e não recebe o id da caixa' do
      stub_pagina
      create(:conversation, account: account, inbox: inbox)
      agente = create(:user, account: account, role: :agent)

      page = tela(days: 30, user: agente).perform[:page]

      expect(page[:messages]).to eq(count: nil, inbox_id: nil)
    end

    it 'conta só as conversas que a pessoa vê' do
      stub_pagina
      agente = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agente, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, assignee: agente)
      allow(Conversations::PermissionFilterService).to receive(:new).and_call_original

      page = tela(days: 30, user: agente).perform[:page]

      expect(page[:messages]).to eq(count: 1, inbox_id: inbox.id)
      expect(Conversations::PermissionFilterService).to have_received(:new)
        .with(anything, agente, account, for_reading: true)
    end

    it 'pede de novo o acesso quando o token da Página expirou' do
      stub_request(:get, "#{fb}/1001").with(query: hash_including({})).to_return(erro(190, status: 401))

      page = tela(days: 7).perform[:page]

      expect(page).to eq(status: 'needs_permission', name: 'Studio Acme', inbox_id: inbox.id)
    end

    it 'avisa que a Meta está fora quando ela falha por outro motivo' do
      stub_request(:get, "#{fb}/1001").with(query: hash_including({})).to_return(erro(2, status: 500))

      expect { tela(days: 7).perform }.to raise_error(Crm::MetaAds::Organico::Indisponivel)
    end

    it 'guarda a leitura da Meta por 15 minutos, mas conta as conversas na hora' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_pagina
      tela(days: 30).perform
      create(:conversation, account: account, inbox: inbox)

      page = tela(days: 30).perform[:page]

      expect(a_request(:get, "#{fb}/1001").with(query: hash_including({}))).to have_been_made.once
      expect(page[:messages][:count]).to eq(1)
    end
  end

  describe 'Instagram' do
    let(:channel) { create(:channel_instagram, account: account) }
    let(:inbox) { channel.inbox }

    before do
      inbox
      token = instance_double(Instagram::RefreshOauthTokenService, access_token: 'ig-token')
      allow(Instagram::RefreshOauthTokenService).to receive(:new).and_return(token)
    end

    # follows: [quem passou a seguir, quem deixou de seguir], ou nil quando a Meta não manda (menos de 100 seguidores).
    def follows_data(follows)
      return [] unless follows

      [total('follows_and_unfollows', follows.sum,
             breakdown: recorte('follow_type', 'FOLLOWER' => follows.first, 'NON_FOLLOWER' => follows.last))]
    end

    def stub_instagram_janela(dias, anterior:, numeros:)
      query = janela(dias, anterior: anterior)
      stub_request(:get, "#{ig}/me/insights")
        .with(query: hash_including(query.merge(metric: 'reach,views,total_interactions', metric_type: 'total_value')))
        .to_return(json(data: [total('reach', numeros[:reach]), total('views', numeros[:views]),
                               total('total_interactions', numeros[:interacoes])]))
      stub_request(:get, "#{ig}/me/insights")
        .with(query: hash_including(query.merge(metric: 'follows_and_unfollows', breakdown: 'follow_type')))
        .to_return(json(data: follows_data(numeros[:follows])))
    end

    def stub_instagram(dias: 30, follows: [212, 40], anterior: true)
      stub_request(:get, "#{ig}/me")
        .with(query: hash_including(fields: 'username,followers_count'))
        .to_return(json(username: 'studioacme', followers_count: 5230))
      stub_instagram_janela(dias, anterior: false, numeros: { reach: 7640, views: 23_700, interacoes: 1536, follows: follows })
      stub_request(:get, "#{ig}/me/insights")
        .with(query: hash_including(janela(dias).merge(metric: 'reach', breakdown: 'follow_type')))
        .to_return(json(data: [total('reach', 7640, breakdown: recorte('follow_type', 'FOLLOWER' => 2904, 'NON_FOLLOWER' => 4736))]))
      stub_instagram_janela(dias, anterior: true, numeros: { reach: 6400, views: 20_000, interacoes: 1700, follows: [150, 30] }) if anterior
      stub_instagram_media(dias)
    end

    def stub_instagram_media(dias)
      media = [
        { id: 'i1', caption: 'Antes e depois', timestamp: '2026-10-25T10:00:00+0000', permalink: 'https://ig/i1', media_type: 'IMAGE',
          media_url: 'https://img/i1.jpg', like_count: 380, comments_count: 32 },
        { id: 'i2', caption: 'Reels', timestamp: '2026-10-21T10:00:00+0000', permalink: 'https://ig/i2', media_type: 'VIDEO',
          media_url: 'https://video/i2.mp4', thumbnail_url: 'https://img/i2.jpg', like_count: 200, comments_count: 36 }
      ]
      stub_request(:get, "#{ig}/me/media").with(query: hash_including(janela(dias))).to_return(json(data: media))
      { 'i1' => 3340, 'i2' => 2120 }.each do |id, reach|
        stub_request(:get, "#{ig}/#{id}/insights").with(query: hash_including(metric: 'reach')).to_return(json(data: [diario('reach', [reach])]))
      end
    end

    it 'devolve os números do Instagram com quem ainda não segue e os seguidores novos' do
      stub_instagram
      create(:conversation, account: account, inbox: inbox)

      instagram = tela(days: 30).perform[:instagram]

      expect(instagram).to include(status: 'ok', username: 'studioacme', link: 'https://www.instagram.com/studioacme', followers: 5230,
                                   reach: 7640, views: 23_700, interactions: 1536, reach_non_followers: 4736, new_followers: 212)
      expect(instagram[:previous]).to eq(reach: 6400, views: 20_000, interactions: 1700, new_followers: 150)
      expect(instagram[:messages]).to eq(count: 1, inbox_id: inbox.id)
      expect(instagram[:top_posts].pluck(:id, :reach, :interactions, :image_url)).to eq(
        [['i1', 3340, 412, 'https://img/i1.jpg'], ['i2', 2120, 236, 'https://img/i2.jpg']]
      )
      expect(a_request(:get, "#{ig}/me").with(query: hash_including({}), headers: { 'Authorization' => 'Bearer ig-token' })).to have_been_made
    end

    it 'post sem o alcance na Meta fica sem o número, sem derrubar o Instagram' do
      stub_instagram
      stub_request(:get, "#{ig}/i2/insights").with(query: hash_including(metric: 'reach')).to_return(erro(100))

      instagram = tela(days: 30).perform[:instagram]

      expect(instagram[:status]).to eq('ok')
      expect(instagram[:top_posts].pluck(:id, :reach)).to eq([['i1', 3340], ['i2', nil]])
    end

    it 'em 90 dias não compara: a Meta só guarda 90 dias do Instagram' do
      stub_instagram(dias: 90, anterior: false)

      expect(tela(days: 90).perform[:instagram][:previous]).to be_nil
    end

    it 'com menos de 100 seguidores a Meta não manda os seguidores novos' do
      stub_instagram(follows: nil)

      instagram = tela(days: 30).perform[:instagram]

      expect(instagram[:new_followers]).to be_nil
    end

    it 'pede de novo o acesso quando falta instagram_business_manage_insights' do
      stub_request(:get, "#{ig}/me").with(query: hash_including({})).to_return(json(username: 'studioacme', followers_count: 1))
      stub_request(:get, "#{ig}/me/insights").with(query: hash_including({})).to_return(erro(10, status: 403))

      expect(tela(days: 7).perform[:instagram]).to eq(status: 'needs_permission',
                                                      username: 'studioacme', inbox_id: inbox.id)
    end
  end

  it 'sem caixa da Página nem do Instagram, os dois pedem para conectar' do
    result = tela(days: 7).perform

    expect(result).to eq(days: 7, from: '2026-10-21', to: '2026-10-27', page: { status: 'not_connected' },
                         instagram: { status: 'not_connected' })
  end

  it 'Instagram pelo Messenger não conta como Página' do
    canal = create(:channel_instagram_fb_page, account: account, instagram_id: '178400')
    create(:inbox, account: account, channel: canal)

    expect(tela(days: 7).perform[:page]).to eq(status: 'not_connected')
  end

  it 'recusa período fora de 7, 30 e 90 dias' do
    expect { tela(days: 15) }.to raise_error(ArgumentError)
  end
end
