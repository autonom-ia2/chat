require 'rails_helper'

# A resposta da pessoa ao privado volta para a conversa que nasceu do comentário, mesmo resolvida: sem isso, a caixa
# sem "uma conversa por contato" abria conversa nova, sem o comentário no topo e sem a escolha de quem continua.
RSpec.describe Crm::MetaAds::ComentariosIa::Conversa do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:contact) { create(:contact, account: account) }
  let(:escopo) { Conversation.where(account_id: account.id, inbox_id: inbox.id, contact_id: contact.id) }

  def conversa(status:, comentario: true, criada: Time.current)
    create(:conversation, account: account, inbox: inbox, contact: contact, status: status, created_at: criada,
                          additional_attributes: comentario ? { 'meta_ads_comment' => { 'comment_id' => 'c-1' } } : {})
  end

  it 'reabre a conversa do comentário resolvida' do
    do_comentario = conversa(status: :resolved)

    expect(described_class.para_reabrir(escopo)).to eq(do_comentario)
  end

  it 'não mexe em conversa resolvida que não veio de comentário' do
    conversa(status: :resolved, comentario: false)

    expect(described_class.para_reabrir(escopo)).to be_nil
  end

  it 'com outra conversa aberta do contato, a resposta vai para ela' do
    conversa(status: :resolved)
    conversa(status: :open, comentario: false, criada: 3.days.ago)

    expect(described_class.para_reabrir(escopo)).to be_nil
  end

  it 'só a mais recente vale: depois dela, outra conversa já existe' do
    conversa(status: :resolved, criada: 2.days.ago)
    conversa(status: :resolved, comentario: false, criada: 1.day.ago)

    expect(described_class.para_reabrir(escopo)).to be_nil
  end

  it 'conversa do comentário com mais de 7 dias fica como está' do
    conversa(status: :resolved, criada: 8.days.ago)

    expect(described_class.para_reabrir(escopo)).to be_nil
  end

  it 'está nos dois builders de mensagem recebida' do
    expect(Messages::Instagram::BaseMessageBuilder.ancestors).to include(Crm::MetaAds::ComentariosIa::VoltaAoComentario)
    expect(Messages::Facebook::MessageBuilder.ancestors).to include(Crm::MetaAds::ComentariosIa::VoltaAoComentario)
  end
end
