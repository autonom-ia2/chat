require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Ordem do
  it 'do mais barato ao mais caro; empate na ordem da Universal; sem preço por último' do
    planos = [{ 'nome' => 'a', 'preco_total' => '300.0' }, { 'nome' => 'b', 'preco_total' => nil },
              { 'nome' => 'c', 'preco_total' => '100.0' }, { 'nome' => 'd', 'preco_total' => '300.0' }]
    expect(described_class.por_preco(planos).pluck('nome')).to eq(%w[c a d b])
  end

  it 'a recomendada que cairia depois da 1ª folha ocupa a última vaga dela; o resto segue o preço' do
    expect(described_class.com_recomendada_ate(%w[a b c d e f g h], 7, 6)).to eq(%w[a b c d e h f g])
    expect(described_class.com_recomendada_ate(%w[a b c d], 3, 1)).to eq(%w[d a b c])
  end

  it 'a recomendada já na 1ª folha, ou sem recomendada: a ordem do preço não muda' do
    expect(described_class.com_recomendada_ate(%w[a b c d e f g h], 5, 6)).to eq(%w[a b c d e f g h])
    expect(described_class.com_recomendada_ate(%w[a b], nil, 6)).to eq(%w[a b])
  end
end
