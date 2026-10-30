require 'rails_helper'

# Páginas do Facebook por conta (#2195, comum ao #2197): o webhook de Página chega só com o page_id, e daqui sai a conta.
RSpec.describe Crm::MetaAdsPage do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  describe '.account_ids_for' do
    it 'devolve todas as contas em que a Página está' do
      described_class.create!(account: account, page_id: '104882')
      described_class.create!(account: other_account, page_id: '104882')
      described_class.create!(account: other_account, page_id: '555')

      expect(described_class.account_ids_for(104_882)).to contain_exactly(account.id, other_account.id)
    end

    it 'Página que ninguém tem: vazio' do
      expect(described_class.account_ids_for('999')).to eq([])
    end
  end

  describe '.remember!' do
    it 'guarda id e nome como a Graph devolve, ignorando item sem id' do
      described_class.remember!(account, [{ 'id' => 104_882, 'name' => 'Studio Aurora' }, { 'name' => 'Sem id' }, 'lixo'])

      expect(described_class.where(account: account).pluck(:page_id, :name)).to eq([['104882', 'Studio Aurora']])
    end

    it 'atualiza o nome sem mexer no que cada frente assinou' do
      described_class.create!(account: account, page_id: '104882', name: 'Antigo', leadgen_receiving: true, feed_receiving: true)

      described_class.remember!(account, [{ 'id' => '104882', 'name' => 'Studio Aurora' }])

      expect(described_class.find_by(account: account, page_id: '104882'))
        .to have_attributes(name: 'Studio Aurora', leadgen_receiving: true, feed_receiving: true)
    end

    it 'leitura sem nome não apaga o nome guardado' do
      described_class.create!(account: account, page_id: '104882', name: 'Studio Aurora')

      described_class.remember!(account, [{ 'id' => '104882' }])

      expect(described_class.find_by(account: account, page_id: '104882').name).to eq('Studio Aurora')
    end

    it 'a mesma Página repetida na lista não quebra o upsert' do
      described_class.remember!(account, [{ 'id' => '1', 'name' => 'A' }, { 'id' => '1', 'name' => 'A' }])

      expect(described_class.where(account: account).count).to eq(1)
    end

    it 'sem nome não levanta erro, e repetir não duplica' do
      2.times { described_class.remember!(account, [{ 'id' => '104882' }]) }

      expect(described_class.where(account: account).pluck(:page_id, :name)).to eq([['104882', nil]])
    end

    it 'não apaga a Página que sumiu da lista e não cruza contas' do
      described_class.create!(account: account, page_id: '111')

      described_class.remember!(other_account, [{ 'id' => '111', 'name' => 'Da outra conta' }])

      expect(described_class.where(page_id: '111').pluck(:account_id)).to contain_exactly(account.id, other_account.id)
      expect(described_class.find_by(account: account, page_id: '111').name).to be_nil
    end

    it 'corta o nome no limite da coluna e ignora id que não é texto nem número' do
      described_class.remember!(account, [{ 'id' => '1', 'name' => 'a' * 300 }, { 'id' => ['2'] }, { 'id' => { 'x' => 1 } }])

      expect(described_class.where(account: account).pluck(:page_id)).to eq(['1'])
      expect(described_class.find_by(account: account, page_id: '1').name.length).to eq(described_class::NAME_LIMIT)
    end

    it 'lista vazia não faz nada' do
      expect { described_class.remember!(account, []) }.not_to(change(described_class, :count))
    end
  end

  it 'a mesma Página duas vezes na mesma conta é recusada' do
    described_class.create!(account: account, page_id: '104882')

    expect(described_class.new(account: account, page_id: '104882')).not_to be_valid
  end
end
