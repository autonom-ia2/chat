require 'rails_helper'

# E4 (#2897): quando dois registros com a mesma seguradora e o mesmo número são a mesma apólice.
RSpec.describe Carteira::Termo do
  let(:guardada) { termo('2026-03-10', '2027-03-10') }

  def termo(comeca, termina)
    { inicio_vigencia: comeca && Date.iso8601(comeca), fim_vigencia: Date.iso8601(termina) }
  end

  it 'é a mesma apólice, a não ser que uma comece quando a outra termina e termine depois dela' do
    tabela = {
      'igual em tudo' => [termo('2026-03-10', '2027-03-10'), true],
      'o fim corrigido na origem' => [termo('2026-03-10', '2027-04-10'), true],
      'o começo corrigido na origem' => [termo('2026-04-01', '2027-03-10'), true],
      'sem começo, mesmo terminando um ano depois' => [termo(nil, '2028-03-10'), true],
      'a renovação, que começa no dia em que a anterior termina' => [termo('2027-03-10', '2028-03-10'), false],
      'a renovação que começa depois, com um intervalo' => [termo('2027-05-01', '2028-05-01'), false],
      'o termo anterior, que termina no dia em que esta começa' => [termo('2025-03-10', '2026-03-10'), false]
    }

    tabela.each do |caso, (outra, mesma)|
      expect([described_class.mesmo?(guardada, outra), described_class.mesmo?(outra, guardada)]).to eq([mesma, mesma]), caso
    end
  end

  it 'compara a apólice guardada com os dados que chegam' do
    apolice = Carteira::Apolice.new(guardada)

    expect(described_class.mesmo?(apolice, termo('2026-03-10', '2027-04-10'))).to be(true)
    expect(described_class.mesmo?(apolice, termo('2027-03-10', '2028-03-10'))).to be(false)
    expect(described_class.depois?(termo('2027-03-10', '2028-03-10'), apolice)).to be(true)
  end
end
