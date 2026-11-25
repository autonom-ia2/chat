require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Textos do
  describe '.idades' do
    it 'põe "anos" uma vez no fim da lista' do
      expect(described_class.idades([47, 19, 12])).to eq('47, 19 e 12 anos')
      expect(described_class.idades([30])).to eq('30 anos')
    end

    it 'bebê de 1 ano no singular, sem estragar o plural dos outros' do
      expect(described_class.idades([19, 1])).to eq('19 anos e 1 ano')
      expect(described_class.idades([72, 64, 47, 45, 19, 1])).to eq('72, 64, 47, 45, 19 anos e 1 ano')
      expect(described_class.idades([1, 30])).to eq('1 ano e 30 anos')
      expect(described_class.idades([1])).to eq('1 ano')
    end
  end

  describe '.precos_por_pessoa' do
    let(:faixas) do
      [{ 'de' => 0, 'ate' => 17, 'valor' => '50.0' }, { 'de' => 18, 'ate' => 64, 'valor' => '100.0' },
       { 'de' => 65, 'ate' => 85, 'valor' => '200.0' }]
    end

    def plano(total, faixas)
      { 'preco_total' => total, 'idade_minima' => 0, 'idade_maxima' => 85, 'faixas' => faixas }
    end

    it 'junta as idades do mesmo preço, na ordem em que aparecem' do
      expect(described_class.precos_por_pessoa(plano('450.0', faixas), [70, 30, 10, 40]))
        .to eq([['70 anos', 'R$ 200,00'], ['30 e 40 anos', 'R$ 100,00 cada'], ['10 anos', 'R$ 50,00']])
    end

    it 'todos no mesmo preço: uma linha só' do
      expect(described_class.precos_por_pessoa(plano('300.0', faixas), [47, 19, 30]))
        .to eq([['47, 19 e 30 anos', 'R$ 100,00 cada']])
    end

    it 'a soma não fecha com o total: nada, para não inventar divisão' do
      expect(described_class.precos_por_pessoa(plano('320.0', faixas), [47, 19, 30])).to eq([])
    end

    it 'alguém sem faixa: nada' do
      expect(described_class.precos_por_pessoa(plano('150.0', faixas.first(2)), [47, 70])).to eq([])
    end

    it 'um viajante só: nada (o preço dele é o total)' do
      expect(described_class.precos_por_pessoa(plano('100.0', faixas), [47])).to eq([])
    end
  end
end
