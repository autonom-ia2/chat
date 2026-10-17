require 'rails_helper'

RSpec.describe Crm::Memoria::Mescla do
  let(:account) { create(:account) }
  let(:fica) { create(:contact, account: account) }
  let(:absorvido) { create(:contact, account: account) }

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  def fato!(contato, chave, valor, **extra)
    Crm::Memoria::Gravador.gravar!({ account_id: account.id, contact_id: contato.id, escopo: 'contato', tipo: 'fato', chave: chave,
                                     valor: valor, fonte: 'cliente', prova_message_ids: [1], gerado_por: 't' }.merge(extra))
  end

  it 'C1: mesclar leva os fatos do absorvido para o que fica, sem perder linha (o destroy! apagaria em cascata)' do
    email = fato!(absorvido, 'email', 'ana@x.com')

    expect { ContactMergeAction.new(account: account, base_contact: fica, mergee_contact: absorvido).perform }
      .not_to change(Crm::MemoriaFato, :count)
    expect(email.reload.contact_id).to eq(fica.id)
    expect(Contact.exists?(absorvido.id)).to be(false)
  end

  it 'mesma chave nos dois: o mesmo valor expira o do absorvido; valor diferente vira divergente do que fica' do
    fato!(fica, 'cpf', '123')
    igual = fato!(absorvido, 'cpf', '123')
    fato!(fica, 'email', 'a@x.com')
    outro = fato!(absorvido, 'email', 'b@x.com')

    described_class.mesclar!(account: account, absorvido: absorvido, fica: fica)

    expect(igual.reload.expirado_em).to be_present
    expect(outro.reload).to have_attributes(situacao: 'divergente', contact_id: fica.id)
  end

  it 'o mesmo valor com a trava da equipe no absorvido: a trava passa para o que fica' do
    que_fica = fato!(fica, 'cpf', '123')
    fato!(absorvido, 'cpf', '123', fonte: 'pessoa_corrigiu', status: 'confirmado', travado: true, prova_message_ids: [])

    described_class.mesclar!(account: account, absorvido: absorvido, fica: fica)

    expect(que_fica.reload.travado).to be(true)
  end

  it 'não toca fato de contato de outra conta' do
    outra = create(:account)
    de_fora = Crm::Memoria::Gravador.gravar!(account_id: outra.id, contact_id: create(:contact, account: outra).id, escopo: 'contato',
                                             tipo: 'fato', chave: 'cpf', valor: '9', fonte: 'cliente', prova_message_ids: [1], gerado_por: 't')

    described_class.mesclar!(account: account, absorvido: absorvido, fica: fica)

    expect(de_fora.reload.contact_id).not_to eq(fica.id)
  end
end
