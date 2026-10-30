require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Painel do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:alvo) { { 'kind' => 'post', 'perfil' => 'instagram-1', 'post_id' => '1790', 'networks' => ['instagram'] } }
  let(:fonte) { instance_double(Crm::MetaAds::ComentariosIa::Fonte) }
  let(:ve_tudo) { ->(_conversation) { true } }
  let(:painel) { described_class.new(account: account, alvo: alvo, fonte: fonte, conversation_access: ve_tudo) }
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

  it 'sem ver a conversa, sem o caminho dela' do
    acao('1', 'to_you', conversation: conversa(private_reply: nil))
    sem_ver = described_class.new(account: account, alvo: alvo, fonte: fonte, conversation_access: ->(_c) { false })

    expect(sem_ver.payload[:to_see].first[:conversation_path]).to be_nil
  end

  it 'no Facebook, o privado ainda não está liberado (pages_messaging, F4)' do
    facebook = described_class.new(account: account, alvo: alvo.merge('networks' => ['facebook']), fonte: fonte, conversation_access: ve_tudo)

    expect(facebook.payload[:private_available]).to be(false)
  end

  it 'leitura que não ficou pronta: o cuidado vem, sem a lista' do
    allow(fonte).to receive(:ler).and_return({ status: 'needs_permission', linhas: [], escondidas: [] })

    expect(painel.payload).to include(status: 'needs_permission', care: 'on', to_see: [], hidden: [])
  end
end
