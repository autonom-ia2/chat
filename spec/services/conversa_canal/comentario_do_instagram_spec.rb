require 'rails_helper'

# Comentários na caixa (#2215): o contrato com o motor da IA dos comentários (#2212). A conversa só age no comentário
# quando o motor gravou a linha dele ligada a ela, pelo Registro de verdade (sem mock): se o motor mudar rede, ator ou
# o jeito de ligar a conversa, o cartão some e este spec falha.
RSpec.describe ConversaCanal::ComentarioDoInstagram do
  let(:account) { create(:account) }
  let(:canal) { create(:channel_instagram, account: account) }
  let(:comentario) do
    Crm::MetaAds::ComentariosIa::Comentario.new(network: 'instagram', account_id: account.id, inbox_id: canal.inbox.id,
                                                post_id: '17900000000000001', comment_id: '18000000000000001', from_id: '501')
  end
  let(:care) { instance_double(Crm::MetaAdsCommentCare, id: 7) }
  let(:conversation) do
    create(:conversation, account: account, inbox: canal.inbox,
                          additional_attributes: { 'meta_ads_comment' => Crm::MetaAds::ComentariosIa::Conversa.origem(comentario, care) })
  end
  let(:registro) { Crm::MetaAds::ComentariosIa::Registro }

  it 'privado da IA: a linha reivindicada e ligada depois (vincular!) é a prova' do
    registro.reivindicar!(comentario, 'private_reply')
    expect(described_class.da_conversa(conversation)).to be_nil

    registro.vincular!(comentario, 'private_reply', conversation)

    expect(described_class.da_conversa(conversation)&.comment_id).to eq('18000000000000001')
  end

  it 'passagem para a pessoa: a linha gravada com a conversa (gravar!) é a prova' do
    registro.gravar!(comentario, 'to_you', conversation: conversation)

    expect(described_class.da_conversa(conversation)&.post_id).to eq('17900000000000001')
  end
end
