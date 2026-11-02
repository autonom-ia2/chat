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

    it 'com a versão base, salva só sobre a atual; quem editou uma versão velha recebe VersaoMudou', :aggregate_failures do
      v1 = automacao.salvar_versao!(receita: receita(2), autor: autor, base: nil)
      v2 = automacao.salvar_versao!(receita: receita(3), autor: autor, base: v1.id)

      expect { automacao.salvar_versao!(receita: receita(4), autor: autor, base: v1.id) }
        .to raise_error(described_class::VersaoMudou)
      expect { automacao.salvar_versao!(receita: receita(4), autor: autor, base: nil) }
        .to raise_error(described_class::VersaoMudou)
      expect([automacao.reload.versao_ativa, automacao.versoes.count]).to eq([v2, 2])
    end
  end

  describe '#assumir_e_religar! (F3.7)' do
    let(:account) { automacao.account }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:condicao) { { 'campo' => { '$valor' => 'contato.atributos.placa' }, 'op' => 'preenchido' } }
    let(:receita) do
      { 'gatilho' => { 'tipo' => 'conversa.resolvida' },
        'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'condicao' => condicao,
                       'entao' => [{ 'id' => 'p2', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }] }] }
    end
    let!(:placa) { create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'placa') }

    it 'liga com a versão que a pessoa viu', :aggregate_failures do
      versao = automacao.salvar_versao!(receita: receita, autor: admin)

      expect(automacao.assumir_e_religar!(admin, versao_id: versao.id)).to be_nil
      expect([automacao.reload.ativa, automacao.ligada_por]).to eq([true, admin])
    end

    it 'outra pessoa salvou depois do que ela viu: VersaoMudou, sem ligar nem trocar quem ligou', :aggregate_failures do
      vista = automacao.salvar_versao!(receita: receita, autor: admin)
      automacao.salvar_versao!(receita: receita, autor: create(:user, account: account, role: :administrator))

      expect { automacao.assumir_e_religar!(admin, versao_id: vista.id) }.to raise_error(described_class::VersaoMudou)
      expect([automacao.reload.ativa, automacao.ligada_por]).to eq([false, nil])
    end

    it 'a receita deixou de rodar depois de salva (atributo apagado): recusa e não liga', :aggregate_failures do
      versao = automacao.salvar_versao!(receita: receita, autor: admin)
      placa.destroy!

      expect(automacao.assumir_e_religar!(admin, versao_id: versao.id)).to eq('receita_com_problema')
      expect([automacao.reload.ativa, automacao.ligada_por]).to eq([false, nil])
    end

    it 'sem versão salva: recusa', :aggregate_failures do
      expect(automacao.assumir_e_religar!(admin, versao_id: nil)).to eq('sem_versao')
      expect(automacao.reload.ativa).to be(false)
    end
  end
end
