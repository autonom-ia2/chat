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

    it 'não reaproveita a etiqueta da lista apagada: a lista nova ganha sufixo e nasce vazia' do
      etiqueta = described_class.criar(account: account, name: 'Dicas do mês').label
      ana = create(:contact, account: account, email: 'ana@exemplo.com')
      ana.update_labels([etiqueta.title])
      etiqueta.email_list.destroy!

      nova = described_class.criar(account: account, name: 'Dicas do mês')

      expect(nova.label).not_to eq(etiqueta)
      expect(nova.label.title).to eq('lista-email-dicas-do-mes-2')
      expect(nova.contatos).to be_empty
    end

    it 'etiqueta "lista-email-x" posta em contato sem passar pela tela de etiquetas não põe ninguém na lista "x"' do
      ana = create(:contact, account: account, email: 'ana@exemplo.com')
      ana.update_labels(['lista-email-x'])
      bia = create(:contact, account: account, email: 'bia@exemplo.com')
      bia.update_labels(['Lista-Email-X-2'])
      expect(account.labels.where('title LIKE ?', 'lista-email-%')).to be_empty

      lista = described_class.criar(account: account, name: 'x')

      expect(lista).to be_persisted
      expect(lista.label.title).to eq('lista-email-x-3')
      expect(lista.contatos).to be_empty
      expect(described_class.contagens(account, [lista])[lista.id]).to eq(contatos: 0, recebem: 0)
    end

    it 'não reaproveita etiqueta da conta que não é de lista (criada antes da trava do prefixo)' do
      antiga = build(:label, account: account, title: 'lista-email-x')
      antiga.save!(validate: false)

      expect(described_class.criar(account: account, name: 'x').label).to have_attributes(title: 'lista-email-x-2')
      expect(antiga.reload.email_list).to be_nil
    end

    it 'não aceita o mesmo nome nem um nome que daria a mesma etiqueta, e não deixa etiqueta sobrando' do
      described_class.criar(account: account, name: 'Dicas do mês')

      repetido = described_class.criar(account: account, name: 'Dicas do mês')
      parecido = described_class.criar(account: account, name: 'dicas do mes')

      expect(repetido.errors.details[:name]).to include(a_hash_including(error: :taken))
      expect(parecido.errors.details[:name]).to include(a_hash_including(error: :taken))
      expect(account.labels.where('title LIKE ?', 'lista-email-%').count).to eq(1)
    end

    it 'dois pedidos ao mesmo tempo: o que bate no índice único volta como nome repetido, não como erro' do
      etiquetas = account.labels
      allow(account).to receive(:labels).and_return(etiquetas)
      allow(etiquetas).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      lista = described_class.criar(account: account, name: 'Dicas do mês')

      expect(lista).not_to be_persisted
      expect(lista.errors.details[:name]).to include(a_hash_including(error: :taken))
      expect(described_class.count).to eq(0)
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

  describe 'a etiqueta da lista' do
    it 'não troca de título: o público da campanha mudaria sem a lista mudar' do
      etiqueta = described_class.criar(account: account, name: 'Dicas do mês').label

      expect(etiqueta.update(title: 'outra')).to be(false)
      expect(etiqueta.errors.details[:title]).to include(a_hash_including(error: :email_list_locked))
      expect(etiqueta.reload.title).to eq('lista-email-dicas-do-mes')
    end

    it 'o prefixo das listas não vale para etiqueta criada ou renomeada à mão' do
      criada = account.labels.new(title: 'lista-email-vip')
      renomeada = create(:label, account: account, title: 'vip')

      expect(criada).not_to be_valid
      expect(criada.errors.details[:title]).to include(a_hash_including(error: :email_list_reserved))
      expect(renomeada.update(title: 'lista-email-vip')).to be(false)
    end

    it 'etiqueta comum continua livre para renomear' do
      etiqueta = create(:label, account: account, title: 'vip')

      expect(etiqueta.update(title: 'cliente-vip')).to be(true)
    end
  end

  it 'recusa etiqueta de outra conta' do
    lista = described_class.new(account: account, name: 'X', label: create(:label, title: 'outra-conta'))

    expect(lista).not_to be_valid
    expect(lista.errors.details[:label]).to include(a_hash_including(error: :invalid))
  end

  describe 'quem está na lista' do
    let(:lista) { described_class.criar(account: account, name: 'Dicas do mês') }

    it 'contatos são os da conta com a etiqueta; elegíveis têm e-mail, não pediram para não receber e não estão bloqueados' do
      ana = create(:contact, account: account, email: 'ana@exemplo.com')
      sem_email = create(:contact, account: account, email: nil, phone_number: '+5511988887777')
      recusou = create(:contact, account: account, email: 'bia@exemplo.com')
      fora = create(:contact, account: account, email: 'caio@exemplo.com')
      bloqueado = create(:contact, account: account, email: 'dani@exemplo.com', blocked: true)
      [ana, sem_email, recusou, bloqueado].each { |contato| contato.update_labels([lista.label.title]) }
      recusou.opt_out!(source: 'manual')

      expect(lista.contatos).to contain_exactly(ana, sem_email, recusou, bloqueado)
      expect(lista.elegiveis).to contain_exactly(ana)
      expect(described_class.contagens(account, [lista])[lista.id]).to eq(contatos: 4, recebem: 1)
      expect(lista.contatos).not_to include(fora)
    end

    it 'contatos e contagens usam o mesmo critério: a etiqueta com maiúscula conta, e o contato conta uma vez' do
      ana = create(:contact, account: account, email: 'ana@exemplo.com')
      bia = create(:contact, account: account, email: 'bia@exemplo.com')
      ana.update_labels([lista.label.title])
      maiuscula = ActsAsTaggableOn::Tag.create!(name: 'Lista-Email-Dicas-Do-Mes')
      [ana, bia].each { |contato| ActsAsTaggableOn::Tagging.create!(tag: maiuscula, taggable: contato, context: 'labels') }

      expect(lista.contatos).to contain_exactly(ana, bia)
      expect(described_class.contagens(account, [lista])[lista.id]).to eq(contatos: 2, recebem: 2)
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
