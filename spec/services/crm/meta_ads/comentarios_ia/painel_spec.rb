require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Painel do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:alvo) { { 'kind' => 'post', 'perfil' => 'instagram-1', 'post_id' => '1790', 'networks' => ['instagram'] } }
  let(:fonte) { instance_double(Crm::MetaAds::ComentariosIa::Fonte) }
  let(:ve_tudo) { ->(_conversation) { true } }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:painel) { described_class.new(account: account, alvo: alvo, fonte: fonte, conversation_access: ve_tudo, viewer: admin) }
  let!(:care) do
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1790', offer: nil, para_quem: 'Quem pedir o e-book')
  end

  def linha(id, dias: 1, momento: dias.days.ago)
    { id: id, network: 'instagram', author: "pessoa#{id}", text: "texto #{id}", momento: momento, inbox_id: inbox.id, post_id: '1790' }
  end

  def acao(comment_id, action, conversation: nil)
    Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: comment_id, action: action, actor: 'ai',
                                      conversation: conversation)
  end

  def conversa(private_reply:, respondeu: false)
    origem = { 'care_id' => care.id, 'private_reply' => private_reply }.compact
    conversation = create(:conversation, account: account, inbox: inbox, additional_attributes: { 'meta_ads_comment' => origem })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi') if respondeu
    conversation
  end

  before do
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1'), linha('2'), linha('3'), linha('4'), linha('5', dias: 9)],
                                               escondidas: [linha('6'), linha('7')] })
  end

  it 'diz o porquê de cada comentário que ficou com o dono e o que a IA escondeu' do
    acao('1', 'ai_seen')
    acao('1', 'to_you', conversation: conversa(private_reply: nil))
    acao('2', 'ai_seen')
    acao('2', 'private_reply_failed')
    acao('3', 'ai_seen')
    acao('6', 'ai_seen')
    acao('6', 'hide')

    payload = painel.payload

    expect(payload[:to_see].map { |item| [item[:id], item[:kind]] })
      .to eq([%w[1 complaint], %w[2 failed], %w[3 skipped], %w[4 waiting], %w[5 older]])
    expect(payload[:to_see].first[:conversation_path]).to start_with("/app/accounts/#{account.id}/conversations/")
    expect(payload[:hidden].pluck(:id)).to eq(%w[6])
    expect(payload).to include(care: 'on', care_id: care.id, para_quem: 'Quem pedir o e-book', unanswered: 4, older: 1,
                               private_available: true)
  end

  it 'sem cuidado gravado, care_id nulo: a tela do passo 1 só anexa depois de ligar (#2487)' do
    care.destroy!

    expect(painel.payload).to include(care: 'off', care_id: nil)
  end

  it 'recebeu no privado e respondeu, pelas conversas que nasceram do cuidado; não era o caso, pelo que a IA leu' do
    conversa(private_reply: true, respondeu: true)
    conversa(private_reply: true)
    conversa(private_reply: nil)
    acao('3', 'ai_seen')

    expect(painel.payload[:results]).to eq(sent: 2, replied: 1, skipped: 1)
  end

  it 'a IA não cuidou (Meta ou IA fora do ar, teto, sem certeza): "não cuidei", não "não era o caso"' do
    acao('3', 'ai_seen')
    acao('3', 'ai_unread')

    expect(painel.payload[:to_see].find { |item| item[:id] == '3' }[:kind]).to eq('unread')
  end

  it 'o privado que a Meta não confirmou: "pode ter saído", para o dono conferir no direct' do
    acao('3', 'ai_seen')
    acao('3', 'private_reply_unsure', conversation: conversa(private_reply: nil))

    expect(painel.payload[:to_see].find { |item| item[:id] == '3' }).to include(kind: 'unsure', conversation_path: be_present)
  end

  it 'a pessoa já tinha o privado deste post: "já recebeu", não "não se aplica"; e não há aviso automático para a tela' do
    acao('3', 'ai_seen')
    acao('3', 'private_reply_already')
    account.update!(locale: 'pt_BR')

    payload = painel.payload

    expect(payload[:to_see].find { |item| item[:id] == '3' }[:kind]).to eq('already_sent')
    expect(payload[:results][:skipped]).to eq(0)
    expect(payload).not_to have_key(:automatic_note)
  end

  it 'o que a IA fez em outra conta, com o mesmo id de comentário, não entra' do
    outra = create(:account)
    Crm::MetaAdsCommentAction.record!(account: outra, network: 'instagram', comment_id: '1', action: 'to_you', actor: 'ai')
    Crm::MetaAdsCommentAction.record!(account: outra, network: 'instagram', comment_id: '6', action: 'hide', actor: 'ai')

    payload = painel.payload

    expect(payload[:to_see].find { |item| item[:id] == '1' }[:kind]).to eq('waiting')
    expect(payload[:hidden]).to be_empty
  end

  it 'sem ver a conversa, sem o caminho dela' do
    acao('1', 'to_you', conversation: conversa(private_reply: nil))
    sem_ver = described_class.new(account: account, alvo: alvo, fonte: fonte, conversation_access: ->(_c) { false },
                                  viewer: admin)

    expect(sem_ver.payload[:to_see].first[:conversation_path]).to be_nil
  end

  it 'no Facebook, o privado ainda não está liberado (pages_messaging, F4)' do
    facebook = described_class.new(account: account, alvo: alvo.merge('networks' => ['facebook']), fonte: fonte, conversation_access: ve_tudo,
                                   viewer: admin)

    expect(facebook.payload[:private_available]).to be(false)
  end

  it 'no Facebook, a pergunta que era o caso fica com o dono (no_private), não como "não se aplica"' do
    facebook = described_class.new(account: account, alvo: alvo.merge('networks' => ['facebook']), fonte: fonte, conversation_access: ve_tudo,
                                   viewer: admin)
    allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1').merge(network: 'facebook')], escondidas: [] })
    Crm::MetaAdsCommentAction.record!(account: account, network: 'facebook', comment_id: '1', action: 'ai_seen', actor: 'ai')
    Crm::MetaAdsCommentAction.record!(account: account, network: 'facebook', comment_id: '1', action: 'kept_for_owner', actor: 'ai')

    payload = facebook.payload

    expect(payload[:to_see].map { |item| [item[:id], item[:kind]] }).to eq([%w[1 no_private]])
    expect(payload[:results][:skipped]).to eq(0)
  end

  it '"respondeu" olha só as conversas enviadas (EXISTS), sem varrer as mensagens da conta' do
    conversa(private_reply: true, respondeu: true)
    consultas = []
    contar = ->(*, payload) { consultas << payload[:sql] if payload[:sql].include?('messages') }

    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { described_class.resultados(account, [care], admin) }

    expect(consultas).to all(include('EXISTS'))
    expect(consultas.join).not_to include('IN (SELECT "messages"."conversation_id"')
    expect(described_class.resultados(account, [care], admin)).to eq(care.id => { sent: 1, replied: 1 })
  end

  it 'vários cuidados em duas consultas (enviadas e respondidas), com zero para quem não tem nada' do
    conversa(private_reply: true, respondeu: true)
    outro = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1791', offer: nil, para_quem: 'Quem pedir')
    consultas = []
    contar = ->(*, payload) { consultas << payload[:sql] if payload[:sql].include?('conversations') }

    resultado = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') do
      described_class.resultados(account, [care, outro], admin)
    end

    expect(resultado).to eq(care.id => { sent: 1, replied: 1 }, outro.id => { sent: 0, replied: 0 })
    expect(consultas.size).to eq(2)
  end

  it 'conta só as conversas que quem abre a tela vê' do
    conversa(private_reply: true, respondeu: true)
    agente = create(:user, account: account, role: :agent)
    outra_caixa = create(:inbox, account: account)
    create(:inbox_member, user: agente, inbox: outra_caixa)

    expect(described_class.resultados(account, [care], agente)).to eq(care.id => { sent: 0, replied: 0 })

    create(:inbox_member, user: agente, inbox: inbox)
    expect(described_class.resultados(account, [care], agente)).to eq(care.id => { sent: 1, replied: 1 })
  end

  describe 'chegaram antes de ligar' do
    before { care.update!(started_at: 2.days.ago) }

    it 'só é "antes" o que chegou antes de ligar; o que chegou depois e a IA ainda não leu fica na fila dela, até 10 min' do
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', dias: 3), linha('2', momento: 9.minutes.ago),
                                                                           linha('3', dias: 1), linha('4', dias: 9)], escondidas: [] })
      acao('3', 'ai_seen')

      payload = painel.payload

      expect(payload[:to_see].map { |item| [item[:id], item[:kind]] }).to eq([%w[1 waiting], %w[3 skipped], %w[4 older]])
      expect(payload).to include(unanswered: 1, older: 1)
    end

    # #2519: nada some em silêncio. O evento pode não ter chegado (ou o job, morrido): sem nenhuma ação da IA em 10 min,
    # o comentário vem para o dono, com o selo de que a IA não o pegou.
    it 'chegou depois de ligar e a IA não fez nada em 10 min: fica com o dono (not_caught)' do
      chegou = 11.minutes.ago
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', momento: chegou), linha('2', momento: 9.minutes.ago),
                                                                           linha('3', momento: 2.hours.ago)], escondidas: [] })
      acao('3', 'ai_seen')

      to_see = painel.payload[:to_see]
      expect(to_see.map { |item| [item[:id], item[:kind]] }).to eq([%w[1 not_caught], %w[3 skipped]])
      # A tela mostra há quanto tempo a pessoa espera ("há 11 minutos").
      expect(to_see.first[:created_time]).to eq(chegou.iso8601)
    end

    it 'o que a pessoa já respondeu, escondeu ou apagou pela plataforma não é "não vi a tempo"' do
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', momento: 1.hour.ago), linha('2', momento: 1.hour.ago)],
                                                 escondidas: [] })
      Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: '1', action: 'reply', actor: 'user',
                                        user: admin)

      expect(painel.payload[:to_see].map { |item| [item[:id], item[:kind]] }).to eq([%w[2 not_caught]])
    end

    # #2454: "Os N que já estão aqui" do Ligar conta também as respostas de cliente, só com a flag meta_ads_comentarios_ia.
    it 'as respostas de cliente entram no "Ler e mandar" só com a flag meta_ads_comentarios_ia' do
      respostas = [linha('1a', dias: 3).merge(parent_id: '1'), linha('2a', dias: 1).merge(parent_id: '2')]
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', dias: 3), linha('2', momento: 5.minutes.ago)], escondidas: [],
                                                 respostas_que_esperam: respostas })

      expect(painel.payload).to include(unanswered: 1, older: 0)

      account.enable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)
      payload = described_class.new(account: account.reload, alvo: alvo, fonte: fonte, conversation_access: ve_tudo, viewer: admin).payload
      expect(payload).to include(unanswered: 2, older: 0)
      expect(payload[:to_see].pluck(:id)).to eq(%w[1])
    end

    it 'cuidado pausado: o que chegou depois de ligar e a IA não leu fica com o dono (paused), não some' do
      care.update!(status: 'paused')
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', dias: 3), linha('2', dias: 1)], escondidas: [] })

      expect(painel.payload[:to_see].map { |item| [item[:id], item[:kind]] }).to eq([%w[1 waiting], %w[2 paused]])
    end

    it 'religar recomeça a contar daqui: o que chegou com o cuidado pausado vira "antes de ligar" e o "Ler e mandar" volta' do
      care.update!(status: 'paused', read_old_at: 1.day.ago)
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('2', dias: 1)], escondidas: [] })

      painel.salvar!(message: care.message, para_quem: care.para_quem, phrases: care.phrases, status: 'on', user: nil)

      expect(care.reload).to have_attributes(status: 'on', read_old_at: nil, started_at: be_within(5.seconds).of(Time.current))
      expect(painel.payload[:to_see].map { |item| [item[:id], item[:kind]] }).to eq([%w[2 waiting]])
    end

    it 'salvar com o cuidado já ligado não mexe no começo' do
      inicio = care.started_at

      painel.salvar!(message: care.message, para_quem: care.para_quem, phrases: care.phrases, status: 'on', user: nil)

      expect(care.reload.started_at).to be_within(1.second).of(inicio)
    end
  end

  describe '#salvar!' do
    let(:alvo_novo) { alvo.merge('post_id' => '1791') }
    let(:corpo) { { message: 'Oi', para_quem: 'Quem pedir', phrases: ['Te chamei'], status: 'on', user: nil } }

    # #2520: o Facebook só manda o comentário com o `feed` da Página assinado; o Instagram não precisa.
    it 'ligar um cuidado do Facebook assina o feed da Página; o do Instagram não' do
      account.enable_features!('meta_ads_comentarios_facebook')
      pagina = create(:channel_facebook_page, account: account, page_id: '555')
      alvo_fb = { 'kind' => 'post', 'perfil' => "facebook-#{pagina.inbox.id}", 'post_id' => '555_1', 'networks' => ['facebook'],
                  'inbox_id' => pagina.inbox.id }
      facebook = described_class.new(account: account, alvo: alvo_fb, fonte: fonte, conversation_access: ve_tudo, viewer: admin)

      expect { facebook.salvar!(**corpo) }.to have_enqueued_job(Crm::MetaAds::ComentariosIa::AssinarFeedJob).with(account.id, '555')
      expect { painel.salvar!(**corpo) }.not_to have_enqueued_job(Crm::MetaAds::ComentariosIa::AssinarFeedJob)
    end

    it 'duas abas ligando o mesmo post ao mesmo tempo: a segunda relê o cuidado e aplica por cima, sem erro' do
      aba1 = described_class.new(account: account, alvo: alvo_novo, fonte: fonte, conversation_access: ve_tudo, viewer: admin)
      aba2 = described_class.new(account: account, alvo: alvo_novo, fonte: fonte, conversation_access: ve_tudo, viewer: admin)
      aba2.cuidado # a aba 2 leu antes de a aba 1 gravar
      aba1.salvar!(**corpo)

      expect { aba2.salvar!(**corpo, message: 'Oi de novo') }.not_to raise_error
      expect(Crm::MetaAdsCommentCare.where(target_id: '1791').sole.message).to eq('Oi de novo')
    end

    it 'a corrida que passa da validação e para no índice único (RecordNotUnique) também relê e aplica' do
      aba = described_class.new(account: account, alvo: alvo_novo, fonte: fonte, conversation_access: ve_tudo, viewer: admin)
      outra = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1791')
      chamadas = 0
      allow(Crm::MetaAdsCommentCare).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        chamadas += 1
        chamadas == 1 ? nil : original.call(*args, **kwargs)
      end
      allow_any_instance_of(Crm::MetaAdsCommentCare).to receive(:valid?).and_return(true) # rubocop:disable RSpec/AnyInstance

      aba.salvar!(**corpo)

      expect(outra.reload.message).to eq('Oi')
    end
  end

  describe '#ler_antigos!' do
    it 'a fila recusou o job: a marca sai e o erro sobe, para o dono tentar de novo' do
      allow(Crm::MetaAds::ComentariosIa::LerAntigosJob).to receive(:perform_later).and_raise(RedisClient::CannotConnectError)

      expect { painel.ler_antigos! }.to raise_error(RedisClient::CannotConnectError)
      expect(care.reload.read_old_at).to be_nil
    end

    it 'trava atômica: duas chamadas ao mesmo tempo põem um job só' do
      outra_aba = described_class.new(account: account, alvo: alvo, fonte: fonte, conversation_access: ve_tudo, viewer: admin)
      painel.cuidado
      outra_aba.cuidado
      painel.ler_antigos!

      expect { outra_aba.ler_antigos! }.to raise_error(described_class::Error, 'already_read')
      expect(Crm::MetaAds::ComentariosIa::LerAntigosJob).to have_been_enqueued.once
    end
  end

  describe 'o anúncio cujo criativo mudou de post' do
    let(:alvo_do_anuncio) { { 'kind' => 'ad', 'ad_id' => '120', 'networks' => %w[instagram facebook], 'post_ids' => %w[17911 555_777] } }
    let!(:do_anuncio) do
      create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', post_ids: %w[17900], network: 'instagram')
    end

    it 'ao ler, o cuidado passa a ter os posts e as redes de agora: o motor acha o comentário do post novo' do
      described_class.new(account: account, alvo: alvo_do_anuncio, fonte: fonte, conversation_access: ve_tudo, viewer: admin).payload

      expect(do_anuncio.reload).to have_attributes(post_ids: %w[17911 555_777], network: 'both')
      expect(Crm::MetaAdsCommentCare.cuidando(account_id: account.id, network: 'instagram', post_id: '17911', ad_id: nil)).to eq(do_anuncio)
    end

    it 'o cuidado mudou depois de lido (um salvar! ao mesmo tempo): não sobrescreve' do
      tela = described_class.new(account: account, alvo: alvo_do_anuncio, fonte: fonte, conversation_access: ve_tudo, viewer: admin)
      tela.cuidado
      do_anuncio.update_columns(post_ids: %w[17922], network: 'instagram') # rubocop:disable Rails/SkipsModelValidations

      tela.payload

      expect(do_anuncio.reload.post_ids).to eq(%w[17922])
    end

    it 'sem mudança, não grava' do
      do_anuncio.update!(post_ids: %w[17911 555_777], network: 'both')

      expect do
        described_class.new(account: account, alvo: alvo_do_anuncio, fonte: fonte, conversation_access: ve_tudo, viewer: admin).payload
      end.not_to(change { do_anuncio.reload.updated_at })
    end
  end

  it 'leitura que não ficou pronta: o cuidado vem, sem a lista' do
    allow(fonte).to receive(:ler).and_return({ status: 'needs_permission', linhas: [], escondidas: [] })

    expect(painel.payload).to include(status: 'needs_permission', care: 'on', to_see: [], hidden: [])
  end
end
