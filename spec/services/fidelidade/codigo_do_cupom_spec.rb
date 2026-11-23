require 'rails_helper'

# #3100 — o código do cupom de cada pessoa: o começo que a conta escolheu e um fim sorteado sem letras que se confundem,
# um por pessoa e cupom, único na conta.
RSpec.describe Fidelidade::CodigoDoCupom do
  let(:account) { create(:account) }
  let!(:cupom) do
    Fidelidade::Cupom.create!(account: account, nome: 'Volta', oferta_tipo: 'porcentagem', oferta_valor: 10, prefixo: 'VOLTA',
                              validade_dias: 15)
  end
  let!(:ana) { create(:contact, account: account) }

  it 'sorteia "PREFIXO-XXXX" sem 0, O, 1, I nem L, ainda sem enviado_em', :aggregate_failures do
    codigo = described_class.new(cupom).para(ana)

    prefixo, fim = codigo.codigo.split('-')
    expect(prefixo).to eq('VOLTA')
    expect(fim.length).to eq(4)
    expect(fim.chars).to all(satisfy { |letra| described_class::LETRAS.include?(letra) })
    expect(described_class::LETRAS & %w[0 O 1 I L]).to be_empty
    expect(codigo).to have_attributes(account_id: account.id, contact_id: ana.id, enviado_em: nil, vale_ate: nil)
  end

  it 'a mesma pessoa recebe o mesmo código de novo' do
    primeiro = described_class.new(cupom).para(ana)

    expect(described_class.new(cupom).para(ana)).to eq(primeiro)
    expect(Fidelidade::CupomCodigo.count).to eq(1)
  end

  it 'quando o sorteio bate num código que a conta já tem, tenta de novo' do
    outra = create(:contact, account: account)
    Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: outra, codigo: 'VOLTA-AAAA')
    sorteios = %w[A A A A B B B B].map { |letra| described_class::LETRAS.index(letra) }
    allow(SecureRandom).to receive(:random_number).and_return(*sorteios)

    expect(described_class.new(cupom).para(ana).codigo).to eq('VOLTA-BBBB')
  end

  it 'com os códigos de 4 esgotados, passa para 5' do
    outra = create(:contact, account: account)
    Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: outra, codigo: 'VOLTA-AAAA')
    allow(SecureRandom).to receive(:random_number).and_return(described_class::LETRAS.index('A'))

    expect(described_class.new(cupom).para(ana).codigo).to eq('VOLTA-AAAAA')
  end
end
