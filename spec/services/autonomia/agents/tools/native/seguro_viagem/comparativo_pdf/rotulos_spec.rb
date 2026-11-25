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

  describe '.recomendada (a regra trocável)' do
    it 'devolve o índice que `de` marca como recomendada' do
      planos = [plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000'), plano('285.0', 'R$ 60.000'),
                plano('540.0', 'R$ 250.000')]
      expect(described_class.recomendada(planos)).to eq(0)
      expect(described_class.de(planos).index(:recomendada)).to eq(0)
    end

    it 'um plano: ele; nenhum: nil' do
      expect(described_class.recomendada([plano('360.0', 'R$ 100.000')])).to eq(0)
      expect(described_class.recomendada([])).to be_nil
    end
  end

  it '"para médico e hospital": o mesmo nome em todo o documento' do
    expect(described_class.para_medico_e_hospital(plano('1.0', 'R$ 100.000'))).to eq('R$ 100.000 para médico e hospital')
    expect(described_class.para_medico_e_hospital({ 'coberturas' => [] })).to eq('Médico e hospital: não informado')
  end

  describe '.porque' do
    def porque(planos)
      described_class.porque(planos, described_class.de(planos))
    end

    it 'compara com a opção mais barata' do
      planos = [plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000')]
      expect(porque(planos)).to eq('Por R$ 150,00 a mais que a opção mais barata, a proteção para médico e hospital sobe de ' \
                                   'R$ 30.000 para R$ 100.000.')
    end

    it 'cita a de maior cobertura quando ela é outra e custa mais' do
      planos = [plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000'), plano('285.0', 'R$ 60.000'),
                plano('540.0', 'R$ 250.000')]
      expect(porque(planos)).to eq('Por R$ 150,00 a mais que a opção mais barata, a proteção para médico e hospital sobe de ' \
                                   'R$ 30.000 para R$ 100.000. A de maior cobertura custa R$ 180,00 a mais.')
    end

    it 'a recomendada é a mais barata: diz isso, sem comparação inventada' do
      expect(porque([plano('300.0', 'R$ 50.000'), plano('200.0', 'R$ 100.000')]))
        .to eq('É a opção mais barata desta cotação, com R$ 100.000 para médico e hospital.')
      expect(porque([plano('200.0', 'R$ 100.000'), plano('900.0', 'R$ 300.000')]))
        .to eq('É a opção mais barata desta cotação, com R$ 100.000 para médico e hospital. ' \
               'A de maior cobertura custa R$ 700,00 a mais.')
    end

    it 'a mais barata não cobre menos: não diz que a proteção "sobe"' do
      planos = [plano('100.0', 'R$ 100.000'), plano('300.0', 'R$ 50.000')]
      expect(described_class.porque(planos, %i[economica recomendada]))
        .to eq('Custa R$ 200,00 a mais que a opção mais barata, com R$ 50.000 para médico e hospital.')
    end

    it 'um plano só: o valor e o preço dele' do
      expect(porque([plano('360.0', 'R$ 100.000')])).to eq('R$ 100.000 para médico e hospital por R$ 360,00 no total.')
    end
  end
end
