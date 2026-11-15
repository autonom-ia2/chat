require 'rails_helper'

# E7 (#2900): a referência da origem é o que faz a busca de todo dia achar o mesmo seguro em vez de criar outro. O banco
# garante: a mesma referência do conector não entra duas vezes na conta, mas pode existir em outra conta, e quem não
# tem referência (planilha, PDF, à mão) não esbarra no índice. O `up` e o `down` inteiros (índice CONCURRENTLY) são
# exercidos pelo job "Migrations do lote" da CI, não aqui.
RSpec.describe 'AddConectorToCarteira' do
  let(:account) { create(:account) }

  def seguro(conta, ref, origem: 'conector')
    create(:carteira_apolice, account: conta, origem: origem, origem_ref: ref)
  end

  it 'a mesma referência do conector não entra duas vezes na conta' do
    seguro(account, 'ref-exemplo-1')

    expect { seguro(account, 'ref-exemplo-1') }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'a mesma referência em outra conta, ou sem referência, entra' do
    seguro(account, 'ref-exemplo-1')

    expect do
      seguro(create(:account), 'ref-exemplo-1')
      seguro(account, nil, origem: 'planilha')
      seguro(account, nil, origem: 'planilha')
    end.not_to raise_error
  end

  it 'a busca de todo dia nasce desligada' do
    expect(Carteira::RenovacaoConfig.new(account: account).busca_diaria).to be(false)
  end
end
