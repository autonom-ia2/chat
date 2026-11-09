require 'rails_helper'

# G52 (#2760): a lista de e-mail é um nome com uma etiqueta por baixo; estar na lista é ter a etiqueta.
RSpec.describe EmailList do
  let(:account) { create(:account) }

  describe '.criar' do
    it 'cria a lista e a etiqueta dela, com o título tirado do nome' do
      lista = described_class.criar(account: account, name: '  Dicas do   mês ')

      expect(lista).to be_persisted
      expect(lista.name).to eq('Dicas do mês')
      expect(lista.label).to have_attributes(account_id: account.id, title: 'lista-email-dicas-do-mes')
    end

    it 'reaproveita a etiqueta que já existe, com quem já estava nela' do
      etiqueta = create(:label, account: account, title: 'lista-email-dicas-do-mes')

      expect(described_class.criar(account: account, name: 'Dicas do mês').label).to eq(etiqueta)
    end

    it 'não aceita o mesmo nome nem um nome que daria a mesma etiqueta, e não deixa etiqueta sobrando' do
      described_class.criar(account: account, name: 'Dicas do mês')

      repetido = described_class.criar(account: account, name: 'Dicas do mês')
      parecido = described_class.criar(account: account, name: 'dicas do mes')

      expect(repetido.errors.details[:name]).to include(a_hash_including(error: :taken))
      expect(parecido.errors.details[:name]).to include(a_hash_including(error: :taken))
      expect(account.labels.where('title LIKE ?', 'lista-email-%').count).to eq(1)
    end

    it 'recusa nome vazio ou sem letra nem número, sem criar etiqueta' do
      expect(described_class.criar(account: account, name: '  ').errors.details[:name]).to include(a_hash_including(error: :blank))
      expect(described_class.criar(account: account, name: '!!!').errors.details[:name]).to include(a_hash_including(error: :invalid))
      expect(account.labels.count).to eq(0)
    end

    it 'o mesmo nome em outra conta é outra lista' do
      described_class.criar(account: create(:account), name: 'Dicas do mês')

      expect(described_class.criar(account: account, name: 'Dicas do mês')).to be_persisted
    end
  end

  it 'recusa etiqueta de outra conta' do
    lista = described_class.new(account: account, name: 'X', label: create(:label, title: 'outra-conta'))

    expect(lista).not_to be_valid
    expect(lista.errors.details[:label]).to include(a_hash_including(error: :invalid))
  end

  describe 'quem está na lista' do
    let(:lista) { described_class.criar(account: account, name: 'Dicas do mês') }

    it 'contatos são os da conta com a etiqueta; elegíveis têm e-mail e não pediram para não receber' do
      ana = create(:contact, account: account, email: 'ana@exemplo.com')
      sem_email = create(:contact, account: account, email: nil, phone_number: '+5511988887777')
      recusou = create(:contact, account: account, email: 'bia@exemplo.com')
      fora = create(:contact, account: account, email: 'caio@exemplo.com')
      [ana, sem_email, recusou].each { |contato| contato.update_labels([lista.label.title]) }
      recusou.opt_out!(source: 'manual')

      expect(lista.contatos).to contain_exactly(ana, sem_email, recusou)
      expect(lista.elegiveis).to contain_exactly(ana)
      expect(lista.contatos).not_to include(fora)
    end
  end

  it 'apagar a etiqueta apaga a lista e deixa a campanha sem lista' do
    lista = described_class.criar(account: account, name: 'Dicas do mês')
    campanha = create(:email_campaign, account: account)
    campanha.update_columns(email_list_id: lista.id) # rubocop:disable Rails/SkipsModelValidations

    lista.label.destroy!

    expect(described_class.exists?(lista.id)).to be(false)
    expect(campanha.reload.email_list_id).to be_nil
  end
end
