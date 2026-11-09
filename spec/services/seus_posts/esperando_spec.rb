require 'rails_helper'

# Seus posts F2 (#2305): "esperando você" sai de uma chamada por página de posts, com os comentários embutidos (formato
# da chamada real de 29/10, v23), e entra em cada post da lista (SeusPosts::Leitura) só com a flag
# seus_posts_comentarios. Quem já recebeu o privado sai na hora, pelo banco.
RSpec.describe SeusPosts::Esperando do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agora) { Time.zone.parse('2026-10-29 12:00:00') }
  let(:fb) { 'https://graph.facebook.com/v23.0' }
  let(:ig) { 'https://graph.instagram.com/v23.0' }
  let(:periodo) { Crm::MetaAds::Organico::Periodo.new(30, zona: Time.zone) }
  let(:comentarios_ig) { Meta::AdsGraphClient::SeusPosts::SEUS_POSTS_INSTAGRAM_COMMENTS_FIELDS }
  let(:comentarios_fb) { Meta::AdsGraphClient::SeusPosts::SEUS_POSTS_PAGE_COMMENTS_FIELDS }

  around do |example|
    travel_to(agora) { example.run }
  end

  before do
    Rails.cache.clear
    Current.account = account
  end

  after { Current.reset }

  def json(data, status: 200)
    { status: status, body: data.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def comentario(id, autor, extra = {})
    { 'id' => id, 'from' => { 'id' => autor } }.merge(extra)
  end

  describe 'Instagram' do
    let(:canal) { create(:channel_instagram, account: account, instagram_id: '900') }

    def stub_comentarios(posts)
      stub_request(:get, "#{ig}/me/media").with(query: hash_including('fields' => comentarios_ig)).to_return(json({ 'data' => posts }))
    end

    it 'conta só o comentário de outra pessoa, não escondido e sem resposta da conta' do
      stub_comentarios([{ 'id' => 'p1', 'comments' => { 'data' => [
                         comentario('c1', '501'),
                         comentario('c2', '502', 'hidden' => true),
                         comentario('c3', '503', 'replies' => { 'data' => [comentario('r3', '900')] }),
                         comentario('c4', '504', 'replies' => { 'data' => [comentario('r4', '505')] }),
                         comentario('r3', '900'),
                         comentario('c5', '900')
                       ] } }])

      resultado = described_class.new(channel: canal, periodo: periodo).perform

      expect(resultado).to eq(status: 'ok', pendentes: { 'p1' => { ids: %w[c1 c4], mais: false } })
    end

    it 'resposta sem `from` que a conta publicou pelo painel conta como respondida (#2313)' do
      Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: 'r1', action: 'page_reply', actor: 'user',
                                        user: admin)
      stub_comentarios([{ 'id' => 'p1', 'comments' => { 'data' => [
                         comentario('c1', '501', 'replies' => { 'data' => [{ 'id' => 'r1' }] })
                       ], 'paging' => { 'next' => 'https://graph.instagram.com/next' } } }])

      resultado = described_class.new(channel: canal, periodo: periodo).perform

      expect(resultado[:pendentes]).to eq('p1' => { ids: [], mais: true })
    end

    # #2804: o post impulsionado por aqui tem os comentários do anúncio noutra mídia, uma por anúncio.
    describe 'comentários do anúncio do post' do
      let(:connection) { create_meta_ads_insights_connection(account) }

      def anuncio(ad_id, media_id, ad_account_id: connection.ad_account_id)
        record = Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: SecureRandom.uuid, status: 'created', ad_id: ad_id,
                                                   ad_account_id: ad_account_id, source_post_id: 'p1', source_post_network: 'instagram',
                                                   activated_at: 1.day.ago)
        Crm::MetaAds::Creation::AdMedia.remember(record, { 'creative' => { 'effective_instagram_media_id' => media_id } })
      end

      def stub_midia(media_id, linhas)
        stub_request(:get, "#{ig}/#{media_id}").with(query: hash_including('fields' => comentarios_ig))
                                               .to_return(json({ 'id' => media_id, 'comments' => { 'data' => linhas } }))
      end

      before do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        stub_comentarios([{ 'id' => 'p1', 'comments' => { 'data' => [comentario('c1', '501')] } }])
        anuncio('903', '7903')
        anuncio('904', '7904', ad_account_id: 'act_outra')
        stub_midia('7903', [comentario('a1', '601'), comentario('a2', '602', 'replies' => { 'data' => [comentario('ra2', '900')] })])
      end

      it 'vêm à parte, por anúncio, só os da conta de anúncios conectada agora' do
        account.enable_features!('meta_ads_hub', 'meta_ads_comentarios_instagram')

        resultado = described_class.new(channel: canal, periodo: periodo).perform

        expect(resultado[:pendentes]).to eq('p1' => { ids: %w[c1], mais: false, anuncios: { '903' => { ids: %w[a1], mais: false } } })
        expect(a_request(:get, "#{ig}/7904").with(query: hash_including({}))).not_to have_been_made
      end

      it 'mídia de anúncio fora do ar: os comentários do post continuam; outro anúncio com a mesma mídia não conta em dobro' do
        account.enable_features!('meta_ads_hub', 'meta_ads_comentarios_instagram')
        anuncio('905', '7903')
        anuncio('906', '7906')
        stub_request(:get, "#{ig}/7906").with(query: hash_including('fields' => comentarios_ig))
                                        .to_return(json({ 'error' => { 'code' => 2, 'message' => 'x' } }, status: 503))

        pendentes = described_class.new(channel: canal, periodo: periodo).perform[:pendentes]

        expect(pendentes['p1'][:ids]).to eq(%w[c1])
        expect(pendentes['p1'][:anuncios].size).to eq(1)
        expect(pendentes['p1'][:anuncios].keys.first).to eq('903').or eq('905')
      end

      it 'anúncio sem a mídia guardada ou além do teto: o post vem com anuncios_mais ("pelo menos")' do
        account.enable_features!('meta_ads_hub', 'meta_ads_comentarios_instagram')
        stub_const("#{described_class}::ANUNCIOS_POR_LEITURA", 1)
        anuncio('905', '7905')
        stub_midia('7905', [comentario('a9', '609')])
        Crm::MetaAdsCreatedObject.create!(account: account, idempotency_key: SecureRandom.uuid, status: 'created', ad_id: '906',
                                          ad_account_id: connection.ad_account_id, source_post_id: 'p1', source_post_network: 'instagram',
                                          activated_at: 1.hour.ago)

        pendentes = described_class.new(channel: canal, periodo: periodo).perform[:pendentes]

        expect(pendentes['p1']).to include(anuncios_mais: true)
        expect(pendentes['p1'][:anuncios].size).to eq(1)
      end

      it 'sem Anúncios da Meta ou os comentários do Instagram no anúncio ligados, nem lê a mídia do anúncio' do
        account.enable_features!('meta_ads_hub')

        resultado = described_class.new(channel: canal, periodo: periodo).perform

        expect(resultado[:pendentes]).to eq('p1' => { ids: %w[c1], mais: false })
        expect(a_request(:get, "#{ig}/7903").with(query: hash_including({}))).not_to have_been_made
      end
    end

    it 'sem a permissão de ler comentários: needs_permission, sem quebrar' do
      stub_request(:get, "#{ig}/me/media").with(query: hash_including('fields' => comentarios_ig))
                                          .to_return(json({ 'error' => { 'code' => 10, 'message' => 'x' } }, status: 403))

      expect(described_class.new(channel: canal, periodo: periodo).perform).to eq(status: 'needs_permission')
    end
  end

  describe 'Página' do
    let(:canal) { create(:channel_facebook_page, account: account, page_id: '700') }

    before { stub_request(:post, %r{graph\.facebook\.com/.*/subscribed_apps}).to_return(json({ 'success' => true })) }

    it 'conta o comentário de primeiro nível sem resposta da Página' do
      linhas = [comentario('1_10', '501'), comentario('1_11', '502', 'is_hidden' => true),
                comentario('1_12', '503', 'comments' => { 'data' => [comentario('1_13', '700')] }), comentario('1_14', '700')]
      stub_request(:get, "#{fb}/700/published_posts").with(query: hash_including('fields' => comentarios_fb))
                                                     .to_return(json({ 'data' => [{ 'id' => '700_1', 'comments' => { 'data' => linhas } }] }))

      resultado = described_class.new(channel: canal, periodo: periodo).perform

      expect(resultado).to eq(status: 'ok', pendentes: { '700_1' => { ids: %w[1_10], mais: false } })
    end
  end

  describe 'na lista (SeusPosts::Leitura)' do
    let(:post) { { id: 'p1', created_time: 2.days.ago.iso8601, views: 10 } }

    def lista(user: admin)
      Current.user = user
      viewer = { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
      SeusPosts::Leitura.new(account: account, perfil: nil, days: 30, viewer: viewer).perform[:perfil]
    end

    before do
      create(:channel_instagram, account: account, instagram_id: '900')
      allow(SeusPosts::NumerosInstagram).to receive(:new)
        .and_return(instance_double(SeusPosts::NumerosInstagram, perform: { status: 'ok', username: 'studioacme' }))
      allow(SeusPosts::Posts).to receive(:para)
        .and_return(instance_double(SeusPosts::PostsInstagram, perform: { status: 'ok', posts: [post], normal: {} }))
    end

    it 'sem a flag, os posts vêm como no F1, sem chamar a Meta pelos comentários' do
      allow(described_class).to receive(:new)

      perfil = lista

      expect(perfil[:posts]).to eq([post])
      expect(perfil).not_to have_key(:waiting_status)
      expect(described_class).not_to have_received(:new)
    end

    describe 'com a flag' do
      before { account.enable_features!('seus_posts_comentarios') }

      it 'cada post vem com os que esperam, sem quem já recebeu o privado' do
        allow(described_class).to receive(:new)
          .and_return(instance_double(described_class, perform: { status: 'ok', pendentes: { 'p1' => { ids: %w[c1 c2], mais: false } } }))
        Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: 'c2', action: 'private_reply', actor: 'user',
                                          user: admin, attempted_at: Time.current, confirmed_at: Time.current)

        perfil = lista

        expect(perfil[:waiting_status]).to eq('ok')
        expect(perfil[:posts].first).to include(waiting: 1, waiting_more: false)
      end

      # #2804: os comentários do anúncio entram no "esperando você" de quem pode abrir Anúncios, onde eles estão.
      describe 'com comentários do anúncio' do
        let(:agent) { create(:user, account: account, role: :agent) }

        before do
          account.enable_features!('meta_ads_hub', 'meta_ads_comentarios_instagram')
          pendentes = { 'p1' => { ids: %w[c1], mais: false, anuncios: { '903' => { ids: %w[a1 a2], mais: true } } } }
          allow(described_class).to receive(:new).and_return(instance_double(described_class, perform: { status: 'ok', pendentes: pendentes }))
          Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: 'a2', action: 'private_reply', actor: 'user',
                                            user: admin, attempted_at: Time.current, confirmed_at: Time.current)
        end

        it 'quem abre Anúncios: somam no post, sem quem já recebeu o privado, e cada anúncio diz os seus' do
          expect(lista[:posts].first).to include(waiting: 2, waiting_more: true, waiting_ads: { '903' => 1 })
        end

        it 'anúncio que não deu para ler: "ou mais" só para quem abre Anúncios' do
          pendentes = { 'p1' => { ids: %w[c1], mais: false, anuncios_mais: true } }
          allow(described_class).to receive(:new).and_return(instance_double(described_class, perform: { status: 'ok', pendentes: pendentes }))
          create(:inbox_member, user: agent, inbox: Inbox.last)

          expect(lista[:posts].first).to include(waiting: 1, waiting_more: true)
          expect(lista(user: agent)[:posts].first).to include(waiting: 1, waiting_more: false)
        end

        it 'quem não abre Anúncios: só os do post' do
          create(:inbox_member, user: agent, inbox: Inbox.last)

          post = lista(user: agent)[:posts].first

          expect(post).to include(waiting: 1, waiting_more: false)
          expect(post).not_to have_key(:waiting_ads)
        end
      end

      it 'sem a permissão de ler comentários: waiting nulo (nunca 0), os posts continuam, e a Meta não é chamada a cada lista' do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        allow(described_class).to receive(:new).and_return(instance_double(described_class, perform: { status: 'needs_permission' }))

        lista
        perfil = lista

        expect(described_class).to have_received(:new).once

        expect(perfil[:waiting_status]).to eq('needs_permission')
        expect(perfil[:posts]).to eq([post.merge(waiting: nil)])
      end

      it 'Meta fora na leitura dos comentários: waiting nulo, e os posts continuam' do
        esperando = instance_double(described_class)
        allow(esperando).to receive(:perform).and_raise(Crm::MetaAds::Organico::Indisponivel.new('fora', codigo: 500))
        allow(described_class).to receive(:new).and_return(esperando)

        perfil = lista

        expect(perfil).to include(posts_status: 'ok', waiting_status: 'unavailable')
        expect(perfil[:posts].first[:waiting]).to be_nil
      end
    end
  end
end
