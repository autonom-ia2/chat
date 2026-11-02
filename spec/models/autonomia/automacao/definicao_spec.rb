require 'rails_helper'

RSpec.describe Autonomia::Automacao::Definicao do
  let(:automacao) { create(:autonomia_automacao) }

  it 'nasce desligada (F2.3)' do
    expect(automacao.ativa).to be(false)
    expect(described_class.new.ativa).to be(false)
  end

  it 'recusa origem fora da lista' do
    expect(build(:autonomia_automacao, origem: 'outra')).not_to be_valid
  end

  it 'recusa versão ativa de outra automação' do
    alheia = create(:autonomia_automacao_versao)

    expect(automacao.tap { |definicao| definicao.versao_ativa = alheia }).not_to be_valid
  end

  describe '#salvar_versao! (F2.2)' do
    let(:autor) { create(:user, account: automacao.account) }

    def esperar(dias) = { 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => dias, 'unidade' => 'dias' } }
    def receita(dias) = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [esperar(dias)] }

    it 'salvar duas vezes cria a versão 1 e a 2, e a 1 nunca muda' do
      v1 = automacao.salvar_versao!(receita: receita(2), autor: autor)
      v2 = automacao.salvar_versao!(receita: receita(3), autor: autor)

      expect([v1.numero, v2.numero]).to eq([1, 2])
      expect(automacao.reload.versao_ativa).to eq(v2)
      expect(v1.reload.receita).to eq(receita(2))
      expect(v1.digest).not_to eq(v2.digest)
    end

    it 'não deixa alterar nem apagar a versão gravada' do
      v1 = automacao.salvar_versao!(receita: receita(2))

      expect { v1.update!(receita: receita(3)) }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { v1.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(v1.reload.receita).to eq(receita(2))
    end

    it 'calcula o mesmo digest para a mesma receita em outra ordem' do
      v1 = automacao.salvar_versao!(receita: receita(2))
      v2 = automacao.salvar_versao!(receita: { 'passos' => [esperar(2).to_a.reverse.to_h], 'gatilho' => { 'tipo' => 'conversa.resolvida' } })

      expect(v1.digest).to eq(v2.digest)
    end

    it 'recusa receita que não é objeto' do
      expect { automacao.salvar_versao!(receita: ['passo']) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
