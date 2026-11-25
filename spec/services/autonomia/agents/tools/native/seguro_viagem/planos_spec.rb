require 'rails_helper'

# Valores esperados calculados à mão da fixture `cotacao.json` (R18): dois produtos reais com despesas médicas (2898),
# idade 0..65, e o "Produto Teste Sem DMH" (idade 0..99, sem 2898), que o filtro tira; `valorDoCambio` 5.9702 no topo.
RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Planos do
  let(:resposta) { JSON.parse(file_fixture('../universal/cotacao.json').read) }
  let(:sem_ids) do
    resposta.merge('beneficios' => resposta['beneficios'].map { |b| b.merge('idBeneficio' => b['idBeneficio'] + 90_000) })
  end

  it 'só planos com despesas médicas e hospitalares, com código nosso' do
    planos = described_class.de(resposta, idades: [45])
    expect(planos.pluck('codigo')).to eq(%w[P1 P2])
    expect(planos.pluck('nome')).to eq(['Especial UA 100K BRL', 'Especial UA 30K BRL'])
    expect(planos.pluck('id_produto')).to eq([5_382_451, 5_382_452])
    expect(planos.pluck('id_produto_acordo')).to eq([634_248, 634_249])
    expect(planos).to all(satisfy { |p| p['coberturas'].any? { |c| described_class::IDS_DMH.include?(c['id_beneficio']) } })
  end

  it 'preço, parcelas, câmbio e faixa como a Universal mandou (R5: câmbio = valorDoCambio)' do
    p1, p2 = described_class.de(resposta, idades: [45])
    expect(p1.slice('preco_total', 'valor_moeda', 'moeda', 'max_parcelas', 'cambio', 'idade_minima', 'idade_maxima'))
      .to eq('preco_total' => '360.0', 'valor_moeda' => '360.0', 'moeda' => 'R$', 'max_parcelas' => 12,
             'cambio' => 5.9702, 'idade_minima' => 0, 'idade_maxima' => 65)
    expect(p2.slice('preco_total', 'cambio')).to eq('preco_total' => '210.0', 'cambio' => 5.9702)
    expect(p1['faixas']).to eq([{ 'de' => 0, 'ate' => 65, 'valor' => '120.0', 'valor_moeda' => '120.0' }])
    expect(p2['faixas']).to eq([{ 'de' => 0, 'ate' => 65, 'valor' => '70.0', 'valor_moeda' => '70.0' }])
  end

  it 'câmbio da tarifa quando a resposta não traz valorDoCambio' do
    expect(described_class.de(resposta.except('valorDoCambio'), idades: [45]).pluck('cambio')).to eq([1, 1])
  end

  it 'principais com o texto da Universal, sem prefixo nosso (R5)' do
    esperado = [
      { 'despesas_medicas' => 'R$ 100.000', 'bagagem' => 'R$ 2.000', 'cancelamento' => 'R$ 2.500' },
      { 'despesas_medicas' => 'R$ 30.000', 'bagagem' => 'R$ 1.000', 'cancelamento' => nil }
    ]
    expect(described_class.de(resposta, idades: [45]).pluck('principais')).to eq(esperado)
  end

  it 'valor em branco: moeda e valor em dinheiro' do
    produtos = resposta['produtos'].map do |produto|
      produto.merge('beneficios' => produto['beneficios'].map { |b| b['idBeneficio'] == 2898 ? b.merge('valor' => '') : b })
    end
    expect(described_class.de(resposta.merge('produtos' => produtos), idades: [45]).first.dig('principais', 'despesas_medicas'))
      .to eq('BRL 100000')
  end

  it 'todas as coberturas do produto, com o nome do catálogo' do
    p1, p2 = described_class.de(resposta, idades: [45])
    expect([p1['coberturas'].size, p2['coberturas'].size]).to eq([32, 29])
    expect(p1['coberturas'].first).to eq('id_beneficio' => 2898, 'nome' => 'Despesas Médicas e Hospitalares (por evento)',
                                         'descricao_completa' => '', 'valor' => 'R$ 100.000', 'moeda' => 'BRL')
  end

  it 'catálogo sem id conhecido de despesas médicas não zera os planos e avisa no log' do
    allow(Rails.logger).to receive(:warn)
    expect(described_class.de(sem_ids, idades: [45]).pluck('codigo')).to eq(%w[P1 P2 P3])
    expect(Rails.logger).to have_received(:warn).with(a_string_including('catálogo sem id conhecido de despesas médicas', '92898'))
  end

  it 'nunca leva campo interno da tarifa' do
    texto = JSON.generate(described_class.de(sem_ids, idades: [45]))
    %w[comissao comissaoIntermediario markup rank quotationPorcentagem valorSemDesconto].each do |campo|
      expect(texto).not_to include(campo)
    end
  end

  it 'resumo em reais com duas casas' do
    expect(described_class.resumo(described_class.de(resposta, idades: [45])).pluck('preco_total'))
      .to eq(['R$ 360,00', 'R$ 210,00'])
  end

  it 'tira o produto que não aceita a idade' do
    expect(described_class.de(resposta, idades: [99])).to eq([])
    expect(described_class.de(resposta, idades: [45, 66])).to eq([])
    expect(described_class.de(sem_ids, idades: [99]).pluck('codigo', 'nome')).to eq([['P1', 'Produto Teste Sem DMH']])
  end
end
