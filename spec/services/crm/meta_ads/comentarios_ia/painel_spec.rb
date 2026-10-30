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

  def linha(id, dias: 1)
    { id: id, network: 'instagram', author: "pessoa#{id}", text: "texto #{id}", momento: dias.days.ago, inbox_id: inbox.id, post_id: '1790' }
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
    expect(payload).to include(care: 'on', para_quem: 'Quem pedir o e-book', unanswered: 4, older: 1, private_available: true)
  end

  it 'recebeu no privado e respondeu, pelas conversas que nasceram do cuidado; não era o caso, pelo que a IA leu' do
    conversa(private_reply: true, respondeu: true)
    conversa(private_reply: true)
    conversa(private_reply: nil)
    acao('3', 'ai_seen')

    expect(painel.payload[:results]).to eq(sent: 2, replied: 1, skipped: 1)
  end

  it 'a IA não cuidou (Meta ou Jev fora do ar, teto, sem certeza): "não cuidei", não "não era o caso"' do
    acao('3', 'ai_seen')
    acao('3', 'ai_unread')

    expect(painel.payload[:to_see].find { |item| item[:id] == '3' }[:kind]).to eq('unread')
  end

  it 'o privado que a Meta não confirmou: "pode ter saído", para o dono conferir no direct' do
    acao('3', 'ai_seen')
    acao('3', 'private_reply_unsure', conversation: conversa(private_reply: nil))

    expect(painel.payload[:to_see].find { |item| item[:id] == '3' }).to include(kind: 'unsure', conversation_path: be_present)
  end

  it 'a pessoa já tinha o privado deste post: "já recebeu", não "não se aplica"; e o aviso automático vem no idioma da conta' do
    acao('3', 'ai_seen')
    acao('3', 'private_reply_already')
    account.update!(locale: 'pt_BR')

    payload = painel.payload

    expect(payload[:to_see].find { |item| item[:id] == '3' }[:kind]).to eq('already_sent')
    expect(payload[:results][:skipped]).to eq(0)
    expect(payload[:automatic_note]).to eq(I18n.t('conversations.activity.meta_ads_comment.private_reply_suffix', locale: 'pt_BR'))
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

    it 'só é "antes" o que chegou antes de ligar; o que chegou depois e a IA ainda não leu não fica com o dono' do
      allow(fonte).to receive(:ler).and_return({ status: 'ready', linhas: [linha('1', dias: 3), linha('2', dias: 1), linha('3', dias: 1),
                                                                           linha('4', dias: 9)], escondidas: [] })
      acao('3', 'ai_seen')

      payload = painel.payload

      expect(payload[:to_see].map { |item| [item[:id], item[:kind]] }).to eq([%w[1 waiting], %w[3 skipped], %w[4 older]])
      expect(payload).to include(unanswered: 1, older: 1)
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
    it 'trava atômica: duas chamadas ao mesmo tempo põem um job só' do
      outra_aba = described_class.new(account: account, alvo: alvo, fonte: fonte, conversation_access: ve_tudo, viewer: admin)
      painel.cuidado
      outra_aba.cuidado
      painel.ler_antigos!

      expect { outra_aba.ler_antigos! }.to raise_error(described_class::Error, 'already_read')
      expect(Crm::MetaAds::ComentariosIa::LerAntigosJob).to have_been_enqueued.once
    end
  end

  it 'leitura que não ficou pronta: o cuidado vem, sem a lista' do
    allow(fonte).to receive(:ler).and_return({ status: 'needs_permission', linhas: [], escondidas: [] })

    expect(painel.payload).to include(status: 'needs_permission', care: 'on', to_see: [], hidden: [])
  end
end
