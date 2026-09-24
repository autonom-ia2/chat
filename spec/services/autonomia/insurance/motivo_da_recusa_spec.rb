require 'rails_helper'

# A ÚNICA CATEGORIA É A INSTABILIDADE (chat#612, decisão do CEO de 23/09/2026): a Lia não fala de recusa do risco, e o
# texto do portal não é lido para virar categoria. Quem decide é o `kind` do conector.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  def categoria(texto, kind: 'risco')
    described_class.categoria('kind' => kind, 'text' => texto)
  end

  describe 'o corpus do conector' do
    TextosDoMotivo::CORPUS.each do |texto, kind, _status, esperada|
      it "«#{texto}» (#{kind}) sai #{esperada.inspect}" do
        expect(categoria(texto, kind: kind)).to eq(esperada)
      end
    end
  end

  describe 'recusa do risco nunca vira categoria' do
    { 'conta da corretora' => TextosDoMotivo::CONTA, 'dado da pessoa' => TextosDoMotivo::PESSOA,
      'textos das revisões' => TextosDoMotivo::REVISOES, 'sondas da revisão da sétima rodada' => SondasDoMotivo::REVISAO_7 }
      .each do |grupo, textos|
      it "#{grupo}: nenhum texto sai com categoria" do
        expect(textos.filter_map { |texto| categoria(texto) }).to be_empty
      end
    end

    it 'os textos que antes saíam veículo ou região saem genéricos' do
      ['Tipo de veículo não aceito.', 'CEP sem aceitação.', 'Localidade não aceita.'].each do |texto|
        expect(categoria(texto)).to be_nil
      end
    end
  end

  # chat#323: a seguradora instável não recusou o risco, e a Lia não pode dizer só que ela não fez proposta.
  it 'o kind passageiro é instabilidade, com qualquer texto e sem texto' do
    expect(categoria('Tipo de veículo não aceito.', kind: 'passageiro')).to eq(described_class::INSTABILIDADE)
    expect(described_class.categoria('kind' => 'passageiro')).to eq(described_class::INSTABILIDADE)
  end

  it 'motivo sem kind, com outro kind, ou que não é Hash sai genérico' do
    expect(described_class.categoria('text' => 'Serviço indisponível')).to be_nil
    expect(categoria('Serviço indisponível', kind: 'credencial')).to be_nil
    expect(described_class.categoria('passageiro')).to be_nil
    expect(described_class.categoria(nil)).to be_nil
  end
end
