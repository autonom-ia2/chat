require 'rails_helper'

# #3175 — o job da leitura do PDF que a busca no conector guardou recebe só ids e passa a busca da mesma conta.
RSpec.describe Carteira::Conector::LerPdfJob do
  let(:account) { conta_com_carteira }
  let(:seguro) { criar_apolice(create(:contact, account: account), seguradora: 'Seguradora Exemplo', numero: 'EX-1', origem: 'conector') }
  let(:leitura) { create(:carteira_leitura, account: account, origem: 'conector', estado: 'trazida') }
  let(:leitor) { instance_double(Carteira::Conector::LerPdf, call: true) }

  before { allow(Carteira::Conector::LerPdf).to receive(:new).and_return(leitor) }

  it 'lê o seguro com a busca dele' do
    described_class.perform_now(seguro.id, leitura.id)

    expect(Carteira::Conector::LerPdf).to have_received(:new).with(seguro, leitura: leitura)
    expect(leitor).to have_received(:call)
  end

  it 'a busca de outra conta não vai junto, e o seguro que sumiu não é lido' do
    de_outra = create(:carteira_leitura, origem: 'conector', estado: 'trazida')

    described_class.perform_now(seguro.id, de_outra.id)
    described_class.perform_now(-1, leitura.id)

    expect(Carteira::Conector::LerPdf).to have_received(:new).once.with(seguro, leitura: nil)
  end
end
