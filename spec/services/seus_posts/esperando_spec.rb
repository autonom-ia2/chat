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

      it 'sem a permissão de ler comentários: waiting nulo (nunca 0), e os posts continuam' do
        allow(described_class).to receive(:new).and_return(instance_double(described_class, perform: { status: 'needs_permission' }))

        perfil = lista

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
