require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Registro do
  let(:account) { create(:account) }

  def comentario(comment_id = 'c-1', network: 'instagram')
    Crm::MetaAds::ComentariosIa::Comentario.new(network: network, account_id: account.id, comment_id: comment_id, ad_id: '120')
  end

  it 'reserva o comentário uma vez só: o webhook reenviado sai sem nada' do
    expect(described_class.reservar!(comentario)).to be(true)
    expect(described_class.reservar!(comentario)).to be(false)
    expect(described_class.reservar!(comentario('c-1', network: 'facebook'))).to be(true)
  end

  it 'grava como IA, com o anúncio e a conversa' do
    conversation = create(:conversation, account: account)

    described_class.gravar!(comentario, 'to_you', conversation: conversation)

    expect(Crm::MetaAdsCommentAction.sole)
      .to have_attributes(account_id: account.id, network: 'instagram', comment_id: 'c-1', action: 'to_you', actor: 'ai',
                          ad_id: '120', conversation_id: conversation.id)
  end

  it 'solta o privado recusado sem tocar no que a pessoa fez' do
    described_class.reivindicar!(comentario, 'private_reply')
    Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: 'c-1', action: 'reply', actor: 'user',
                                      user: create(:user, account: account))

    described_class.soltar!(comentario, 'private_reply')

    expect(Crm::MetaAdsCommentAction.pluck(:action, :actor)).to eq([%w[reply user]])
  end

  it 'conta o teto do dia pelos comentários que a IA leu hoje, na conta' do
    described_class.reservar!(comentario('c-1'))
    described_class.reservar!(comentario('c-2'))
    travel_to(1.day.ago) { described_class.reservar!(comentario('c-3')) }
    Crm::MetaAdsCommentAction.record!(account: create(:account), network: 'instagram', comment_id: 'c-9', action: 'ai_seen', actor: 'ai')

    expect(described_class.hoje(account.id)).to eq(2)
  end

  it 'a reivindicação devolve a linha, que o adaptador confirma quando a Meta aceita' do
    reivindicacao = described_class.reivindicar!(comentario, 'private_reply')

    reivindicacao.confirm!

    expect(Crm::MetaAdsCommentAction.sole.confirmed_at).to be_present
  end

  it 'solta só a reserva do privado que nunca saiu e passou de 2 min, de qualquer autor' do
    travel_to(3.minutes.ago) do
      Crm::MetaAdsCommentAction.record!(account: account, network: 'facebook', comment_id: 'c-1', action: 'private_reply', actor: 'user',
                                        user: create(:user, account: account))
      described_class.reivindicar!(comentario('c-2', network: 'facebook'), 'private_reply').attempt!
      described_class.reservar!(comentario('c-1', network: 'facebook'))
    end
    described_class.reivindicar!(comentario('c-3', network: 'facebook'), 'private_reply')

    %w[c-1 c-2 c-3].each { |id| described_class.soltar_abandonada!(comentario(id, network: 'facebook')) }

    expect(Crm::MetaAdsCommentAction.order(:comment_id, :action).pluck(:comment_id, :action))
      .to eq([%w[c-1 ai_seen], %w[c-2 private_reply], %w[c-3 private_reply]])
  end

  it 'vincula a conversa que nasce depois da reivindicação' do
    conversation = create(:conversation, account: account)
    described_class.reivindicar!(comentario, 'private_reply')

    described_class.vincular!(comentario, 'private_reply', conversation)

    expect(Crm::MetaAdsCommentAction.sole.conversation_id).to eq(conversation.id)
  end
end
