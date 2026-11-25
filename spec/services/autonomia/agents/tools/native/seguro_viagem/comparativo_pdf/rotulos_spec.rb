require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos do
  # Um plano no formato de `Planos.de`, só com o que a regra lê: o preço total e as despesas médicas (2898).
  def plano(preco, despesas_medicas)
    { 'nome' => "Plano #{preco}", 'preco_total' => preco.to_s,
      'coberturas' => [{ 'id_beneficio' => 2898, 'valor' => despesas_medicas }] }
  end

  # Os 4 planos da cotação de exemplo: pontos 12 (30K), 34 (60K), 36 (100K) e 59 (250K, fora por ser a maior).
  let(:quatro) do
    [plano('210.0', 'R$ 30.000'), plano('285.0', 'R$ 60.000'), plano('360.0', 'R$ 100.000'), plano('540.0', 'R$ 250.000')]
  end

  it 'nenhum plano: nenhum rótulo' do
    expect(described_class.de([])).to eq([])
  end

  it 'um plano: "opção disponível"' do
    expect(described_class.de([plano('360.0', 'R$ 100.000')])).to eq([:disponivel])
  end

  it 'pontuação da GTA adaptada: os pontos de cada plano' do
    expect(described_class.pontuacoes(quatro)).to eq([12, 34, 36, 59])
  end

  it 'três ou mais: a recomendada é a de mais pontos entre as que não são a econômica nem a maior cobertura' do
    expect(described_class.de(quatro)).to eq([:economica, nil, :recomendada, :maior_cobertura])
  end

  it 'o desconto de preço muda a escolha que só olharia despesas médicas por real' do
    # Por real, o de R$ 200 (500 de cobertura por real) ganharia do de R$ 115 (435 por real); pelos pontos, o de R$ 115
    # (42) ganha do de R$ 200 (37), que custa o dobro da econômica.
    planos = [plano('100.0', 'R$ 20.000'), plano('115.0', 'R$ 50.000'), plano('200.0', 'R$ 100.000'),
              plano('400.0', 'R$ 1.000.000')]
    expect(described_class.pontuacoes(planos)).to eq([12, 42, 37, 59])
    expect(described_class.de(planos)).to eq([:economica, :recomendada, nil, :maior_cobertura])
  end

  it 'dois planos, um em cada ponta: a de mais pontos vira a recomendada e a outra fica com o rótulo dela' do
    expect(described_class.de([plano('360.0', 'R$ 100.000'), plano('210.0', 'R$ 30.000')])).to eq(%i[recomendada economica])
    expect(described_class.pontuacoes([plano('200.0', 'R$ 100.000'), plano('900.0', 'R$ 300.000')])).to eq([48, 15])
    expect(described_class.de([plano('200.0', 'R$ 100.000'), plano('900.0', 'R$ 300.000')]))
      .to eq(%i[recomendada maior_cobertura])
  end

  it 'a mais barata que também cobre mais fica só com "mais econômica"; a recomendada sai das outras' do
    expect(described_class.de([plano('300.0', 'R$ 50.000'), plano('200.0', 'R$ 100.000')])).to eq(%i[recomendada economica])
    planos = [plano('100.0', 'R$ 300.000'), plano('200.0', 'R$ 100.000'), plano('300.0', 'R$ 50.000')]
    expect(described_class.de(planos)).to eq([:economica, :recomendada, nil])
  end

  it 'empate na maior cobertura: o menor preço vence' do
    planos = [plano('400.0', 'R$ 100.000'), plano('300.0', 'R$ 100.000'), plano('100.0', 'R$ 30.000')]
    expect(described_class.de(planos)).to eq(%i[recomendada maior_cobertura economica])
  end

  it 'empate no preço da econômica: mais despesas médicas vence' do
    planos = [plano('200.0', 'R$ 30.000'), plano('200.0', 'R$ 40.000'), plano('500.0', 'R$ 100.000')]
    expect(described_class.de(planos)).to eq(%i[recomendada economica maior_cobertura])
  end

  it 'empate nos pontos: mais despesas médicas vence; persistindo, o menor preço' do
    mais_cobertura = [plano('100.0', 'R$ 20.000'), plano('150.0', 'R$ 40.000'), plano('150.0', 'R$ 45.000'),
                      plano('400.0', 'R$ 1.000.000')]
    expect(described_class.pontuacoes(mais_cobertura)).to eq([12, 30, 30, 59])
    expect(described_class.recomendada(mais_cobertura)).to eq(2)
    mais_barato = [plano('100.0', 'R$ 20.000'), plano('150.0', 'R$ 40.000'), plano('160.0', 'R$ 40.000'),
                   plano('400.0', 'R$ 1.000.000')]
    expect(described_class.pontuacoes(mais_barato)).to eq([12, 30, 30, 59])
    expect(described_class.recomendada(mais_barato)).to eq(1)
  end

  it 'plano sem preço não é a econômica e o termo de preço dele não conta' do
    planos = [plano('100.0', 'R$ 20.000'), plano(nil, 'R$ 60.000'), plano('200.0', 'R$ 50.000')]
    expect(described_class.pontuacoes(planos)).to eq([28, 38, 65])
    expect(described_class.de(planos)).to eq(%i[economica maior_cobertura recomendada])
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

  describe '.recomendada' do
    it 'devolve o índice que `de` marca como recomendada' do
      expect(described_class.recomendada(quatro)).to eq(2)
      expect(described_class.de(quatro).index(:recomendada)).to eq(2)
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
