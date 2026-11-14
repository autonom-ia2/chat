require 'rails_helper'

# E6 (#2899): a chave da leitura paga de PDF, por conta, que nasce desligada.
RSpec.describe Carteira::Leitor::Liberado do
  let(:account) { create(:account) }

  it 'nasce desligada em toda conta, e sem conta também responde false' do
    expect([described_class.para?(account), described_class.para?(nil)]).to eq([false, false])
  end

  it 'liga e desliga só a conta pedida, no atributo interno dela, sem tocar os outros atributos' do
    outra = create(:account)
    account.update!(internal_attributes: { 'autonomia_insurance_enabled' => true })

    described_class.ligar!(account)

    expect([described_class.para?(account.reload), described_class.para?(outra.reload)]).to eq([true, false])
    expect(account.internal_attributes).to eq('autonomia_insurance_enabled' => true, 'carteira_leitura_de_pdf_liberada' => true)

    described_class.desligar!(account)

    expect(described_class.para?(account.reload)).to be(false)
    expect(account.internal_attributes['autonomia_insurance_enabled']).to be(true)
  end

  it 'só o valor verdadeiro liga: texto solto, nulo e falso não ligam' do
    valores = { true => true, 'true' => true, false => false, 'false' => false, nil => false, '' => false }

    valores.each do |valor, ligada|
      account.update!(internal_attributes: { described_class::ATRIBUTO => valor })

      expect(described_class.para?(account)).to be(ligada)
    end
  end

  it 'não depende de quem tem a carteira: é só a chave da leitura' do
    allow(Carteira::Acesso).to receive(:liberada?).and_return(true)

    expect(described_class.para?(account)).to be(false)
  end
end
