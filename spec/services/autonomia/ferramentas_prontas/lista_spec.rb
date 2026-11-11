require 'rails_helper'

# #2858 (F4): a ordem por relevância da busca, antes do corte da lista. Estável dentro de cada grupo (a ordem da fonte).
RSpec.describe Autonomia::FerramentasProntas::Lista do
  describe '.em_ordem' do
    def ordem(nomes, busca)
      described_class.em_ordem(nomes, busca, &:itself)
    end

    it 'primeiro o texto que comeca pela palavra, depois a palavra no comeco de outra, por ultimo no meio de outra' do
      nomes = ['Preparações antiaderentes de porcas e parafusos', 'Histoparafusose', '-- Outros parafusos para madeira',
               '-- Parafusos autoperfurantes', 'Parafusos, pinos ou pernos', 'De parafuso']

      expect(ordem(nomes, 'PARAFUSO')).to eq(['-- Parafusos autoperfurantes', 'Parafusos, pinos ou pernos',
                                              'Preparações antiaderentes de porcas e parafusos', '-- Outros parafusos para madeira',
                                              'De parafuso', 'Histoparafusose'])
    end

    it 'com mais de uma palavra: comecar e comecar por todas, na ordem da busca; sem acento e sem caixa' do
      nomes = ['Estado de mal asmático', 'Asma brônquica alérgica', 'Crise brônquica na asma', 'Asma']

      expect(ordem(nomes, 'asma bronquica')).to eq(['Asma brônquica alérgica', 'Crise brônquica na asma', 'Estado de mal asmático', 'Asma'])
    end

    it 'busca vazia: a ordem da fonte' do
      expect(ordem(%w[b a c], '  ')).to eq(%w[b a c])
    end
  end
end
