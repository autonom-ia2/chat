require 'rails_helper'

RSpec.describe Crm::Memoria::Mescla do
  let(:account) { create(:account) }
  let(:fica) { create(:contact, account: account) }
  let(:absorvido) { create(:contact, account: account) }
  let(:conversa_do_absorvido) { create(:conversation, account: account, contact: absorvido) }

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  it 'C1: mesclar contatos leva a autoria do absorvido para o que fica, sem perder linha (o destroy! apagaria em cascata)' do
    linha = Crm::Memoria::Origem.gravar!(mensagem!(conversa_do_absorvido, :incoming, content: 'meu CPF é 123'))

    expect { ContactMergeAction.new(account: account, base_contact: fica, mergee_contact: absorvido).perform }
      .not_to change(Crm::MensagemOrigem, :count)
    expect(linha.reload.contact_id).to eq(fica.id)
    expect(Contact.exists?(absorvido.id)).to be(false)
  end

  it 'não toca a memória de contato de outra conta' do
    outra = create(:account)
    de_fora = Crm::Memoria::Origem.gravar!(mensagem!(create(:conversation, account: outra), :incoming, content: 'oi'))

    described_class.mesclar!(account: account, absorvido: create(:contact, account: account), fica: fica)

    expect(de_fora.reload.contact_id).not_to eq(fica.id)
  end
end
