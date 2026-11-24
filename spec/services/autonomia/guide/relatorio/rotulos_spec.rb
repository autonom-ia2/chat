require 'rails_helper'

# Como o relatório do Guia escreve o tempo (#3158).
RSpec.describe Autonomia::Guide::Relatorio::Rotulos do
  describe '.tempo' do
    # Zero é tempo medido (resposta fora do expediente): nunca texto vazio.
    it 'escreve zero como zero segundos', :aggregate_failures do
      expect(described_class.tempo(0)).to eq('0 seconds')
      expect(I18n.with_locale(:pt_BR) { described_class.tempo(0.4) }).to eq('0 segundos')
    end

    it 'nada medido é nil' do
      expect(described_class.tempo(nil)).to be_nil
    end

    it 'usa as duas maiores unidades', :aggregate_failures do
      expect(described_class.tempo(178_813)).to eq('2 days and 1 hour')
      expect(I18n.with_locale(:pt_BR) { described_class.tempo(1_200) }).to eq('20 minutos')
    end
  end
end
