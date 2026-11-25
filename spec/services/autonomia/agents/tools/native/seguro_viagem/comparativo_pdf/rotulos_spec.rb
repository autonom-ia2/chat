require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos do
  # Um plano no formato de `Planos.de`, só com o que a regra lê: o preço total e as despesas médicas (2898).
  def plano(preco, despesas_medicas)
    { 'nome' => "Plano #{preco}", 'preco_total' => preco.to_s,
      'coberturas' => [{ 'id_beneficio' => 2898, 'valor' => despesas_medicas }] }
  end

  it 'nenhum plano: nenhum rótulo' do
    expect(described_class.de([])).to eq([])
  end

  it 'um plano: "opção disponível"' do
    expect(described_class.de([plano('360.0', 'R$ 100.000')])).to eq([:disponivel])
  end

  it 'dois planos: a recomendada é a de mais despesas médicas por real; o outro, o mais barato, é a econômica' do
    planos = [plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000')]
    expect(described_class.de(planos)).to eq(%i[recomendada economica])
  end

  it 'dois planos: o mais barato é o recomendado e o outro leva "maior cobertura"' do
    planos = [plano('200.0', 'R$ 100.000'), plano('900.0', 'R$ 300.000')]
    expect(described_class.de(planos)).to eq(%i[recomendada maior_cobertura])
  end

  it 'dois planos: o recomendado é mais barato e cobre mais; o outro fica sem rótulo' do
    planos = [plano('300.0', 'R$ 50.000'), plano('200.0', 'R$ 100.000')]
    expect(described_class.de(planos)).to eq([nil, :recomendada])
  end

  it 'três ou mais: econômica, maior cobertura e, entre os do meio, a de mais despesas médicas por real' do
    planos = [plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000'), plano('285.0', 'R$ 60.000'),
              plano('540.0', 'R$ 250.000')]
    expect(described_class.de(planos)).to eq([:recomendada, :economica, nil, :maior_cobertura])
  end

  it 'o mais barato que também cobre mais fica só com "mais econômica", e ninguém leva "maior cobertura"' do
    planos = [plano('100.0', 'R$ 300.000'), plano('200.0', 'R$ 100.000'), plano('300.0', 'R$ 50.000')]
    expect(described_class.de(planos)).to eq([:economica, :recomendada, nil])
  end

  it 'empate na maior cobertura: o menor preço vence' do
    planos = [plano('400.0', 'R$ 100.000'), plano('300.0', 'R$ 100.000'), plano('100.0', 'R$ 30.000')]
    expect(described_class.de(planos)).to eq(%i[recomendada maior_cobertura economica])
  end

  it 'empate no preço: a ordem da Universal decide a econômica' do
    planos = [plano('200.0', 'R$ 30.000'), plano('200.0', 'R$ 40.000'), plano('500.0', 'R$ 100.000')]
    expect(described_class.de(planos)).to eq([:economica, :recomendada, :maior_cobertura])
  end

  it 'cada plano tem no máximo um rótulo' do
    planos = [plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000'), plano('540.0', 'R$ 250.000')]
    expect(described_class.de(planos).compact).to eq(described_class.de(planos).compact.uniq)
  end

  it 'lê o valor das despesas médicas como número, sem os centavos' do
    expect(described_class.despesas_medicas(plano('1.0', 'R$ 100.000'))).to eq(100_000)
    expect(described_class.despesas_medicas(plano('1.0', 'R$ 1.500,50'))).to eq(1_500)
    expect(described_class.despesas_medicas({ 'coberturas' => [] })).to eq(0)
  end

  it 'sem a cobertura na lista, usa as principais do plano' do
    expect(described_class.despesas_medicas_texto({ 'principais' => { 'despesas_medicas' => 'R$ 60.000' } })).to eq('R$ 60.000')
  end

  it 'a frase do porquê é fixa por rótulo e só usa números do plano' do
    recomendado = plano('360.0', 'R$ 100.000')
    expect(described_class.frase(:recomendada, recomendado))
      .to eq('Equilibra proteção e preço: R$ 100.000 de despesas médicas por R$ 360,00 no total.')
    expect(described_class.frase(:economica, recomendado))
      .to eq('O menor preço desta cotação: R$ 360,00 no total, com R$ 100.000 de despesas médicas.')
    expect(described_class.frase(:maior_cobertura, recomendado))
      .to eq('A maior cobertura de despesas médicas desta cotação: R$ 100.000, por R$ 360,00 no total.')
    expect(described_class.frase(:disponivel, recomendado)).to eq('R$ 100.000 de despesas médicas por R$ 360,00 no total.')
  end
end
