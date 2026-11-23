require 'rails_helper'

# #3100 — as regras do cartão fidelidade: o que a tela pede (regras.js#errosDoPrograma) o servidor também recusa, e a
# conta da compra é a mesma da tela (sem troco).
RSpec.describe Fidelidade::Programa do
  let(:account) { create(:account) }

  def programa(**mudancas)
    described_class.new({ account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                          premio: 'Uma lavagem grátis' }.merge(mudancas))
  end

  it 'aceita o cartão padrão' do
    expect(programa).to be_valid
  end

  it 'recusa meta fora do cartão: de 2 a 20 carimbos, até 100.000 pontos', :aggregate_failures do
    expect(programa(meta: 1)).not_to be_valid
    expect(programa(meta: 21)).not_to be_valid
    expect(programa(tipo: 'pontos', meta: 100_000)).to be_valid
    expect(programa(tipo: 'pontos', meta: 100_001)).not_to be_valid
  end

  it 'recusa regra vazia, prêmio longo, validade fora da lista e outro tipo', :aggregate_failures do
    expect(programa(a_cada_centavos: 0)).not_to be_valid
    expect(programa(ganha: 0)).not_to be_valid
    expect(programa(premio: ' ')).not_to be_valid
    expect(programa(premio: 'x' * 81)).not_to be_valid
    expect(programa(validade_meses: 5)).not_to be_valid
    expect(programa(tipo: 'selos')).not_to be_valid
  end

  it 'um cartão por conta' do
    programa.save!

    expect(programa).not_to be_valid
  end

  it 'a compra dá pelo valor inteiro, sem troco', :aggregate_failures do
    expect(programa.da_compra(12_000)).to eq(2)
    expect(programa(ganha: 3).da_compra(12_000)).to eq(6)
    expect(programa.da_compra(4_999)).to eq(0)
    expect(programa.da_compra(0)).to eq(0)
  end

  it 'perto do prêmio: falta até 20% da meta, no mínimo 1', :aggregate_failures do
    expect(programa(meta: 10).perto_a_partir).to eq(8)
    expect(programa(meta: 2).perto_a_partir).to eq(1)
    expect(programa(tipo: 'pontos', meta: 500).perto_a_partir).to eq(400)
  end

  it 'a tela lê "a cada" em reais' do
    expect(programa.para_a_tela).to include(tipo: 'carimbos', a_cada: 50, moeda: 'BRL', meta: 10)
  end
end
