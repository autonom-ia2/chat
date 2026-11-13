require 'rails_helper'

# E4 (#2897): quando dois registros com a mesma seguradora e o mesmo número são a mesma apólice, e qual dos termos
# guardados é o dos dados que chegam.
RSpec.describe Carteira::Termo do
  let(:guardada) { termo('2026-03-10', '2027-03-10') }

  def termo(comeca, termina)
    { inicio_vigencia: comeca && Date.iso8601(comeca), fim_vigencia: Date.iso8601(termina) }
  end

  it 'é a mesma apólice só quando o começo é igual ou o fim é igual; todo o resto é outro termo' do
    tabela = {
      'igual em tudo' => [termo('2026-03-10', '2027-03-10'), true],
      'o fim corrigido na origem (mesmo começo)' => [termo('2026-03-10', '2027-04-10'), true],
      'o começo corrigido na origem (mesmo fim)' => [termo('2026-04-01', '2027-03-10'), true],
      'sem começo, com o mesmo fim' => [termo(nil, '2027-03-10'), true],
      'sem começo, com outro fim' => [termo(nil, '2028-03-10'), false],
      'a renovação, que começa no dia em que a anterior termina' => [termo('2027-03-10', '2028-03-10'), false],
      'a renovação antecipada, que começa antes de a anterior terminar' => [termo('2027-02-01', '2028-02-01'), false],
      'por cima da guardada, com começo e fim diferentes' => [termo('2026-06-01', '2027-06-01'), false],
      'o termo anterior' => [termo('2025-03-10', '2026-03-10'), false]
    }

    tabela.each do |caso, (outra, mesma)|
      expect([described_class.mesmo?(guardada, outra), described_class.mesmo?(outra, guardada)]).to eq([mesma, mesma]), caso
    end
  end

  it 'dois registros sem começo só são a mesma apólice pelo fim' do
    expect(described_class.mesmo?(termo(nil, '2027-03-10'), termo(nil, '2028-03-10'))).to be(false)
    expect(described_class.mesmo?(termo(nil, '2027-03-10'), termo(nil, '2027-03-10'))).to be(true)
  end

  describe 'escolher o termo guardado dos dados que chegam' do
    let(:renovada) { termo('2027-03-10', '2028-03-10') }

    it 'nenhum com o mesmo começo nem o mesmo fim: é termo novo' do
      expect(described_class.escolher([guardada, renovada], termo('2028-03-10', '2029-03-10'))).to be_nil
      expect(described_class.escolher([], guardada)).to be_nil
    end

    it 'com dois termos guardados e só um que bate (o do mesmo começo), o fim corrigido é dele' do
      expect(described_class.escolher([guardada, renovada], termo('2026-03-10', '2027-12-10'))).to equal(guardada)
    end

    it 'quando um termo tem o mesmo começo e outro o mesmo fim, não desempata: é ambíguo' do
      expect(described_class.escolher([guardada, renovada], termo('2026-03-10', '2028-03-10'))).to eq(described_class::AMBIGUO)
      expect(described_class.escolher([renovada, guardada], termo('2026-03-10', '2028-03-10'))).to eq(described_class::AMBIGUO)
    end

    it 'a única exceção: com mais de um que bate, o ÚNICO igual em começo e fim é o termo (o reenvio idêntico não é recusado)' do
      de_mesmo_comeco = termo('2026-03-10', '2027-06-10')
      sem_comeco = termo(nil, '2027-03-10')

      expect(described_class.escolher([de_mesmo_comeco, guardada], termo('2026-03-10', '2027-03-10'))).to equal(guardada)
      expect(described_class.escolher([guardada, sem_comeco], termo(nil, '2027-03-10'))).to equal(sem_comeco)
    end

    it 'dois termos iguais em começo e fim aos dados: ambíguo' do
      gemea = termo('2026-03-10', '2027-03-10')

      expect(described_class.escolher([guardada, gemea], termo('2026-03-10', '2027-03-10'))).to eq(described_class::AMBIGUO)
    end

    it 'dois termos com o mesmo começo e nenhum igual em tudo: não adivinha' do
      de_mesmo_comeco = termo('2026-03-10', '2027-06-10')

      expect(described_class.escolher([guardada, de_mesmo_comeco], termo('2026-03-10', '2027-09-10'))).to eq(described_class::AMBIGUO)
    end

    it 'compara a apólice guardada com os dados que chegam' do
      apolice = Carteira::Apolice.new(guardada)

      expect(described_class.escolher([apolice], termo('2026-03-10', '2027-04-10'))).to equal(apolice)
      expect(described_class.escolher([apolice], termo('2027-03-10', '2028-03-10'))).to be_nil
    end
  end
end
