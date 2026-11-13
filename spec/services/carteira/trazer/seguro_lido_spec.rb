require 'rails_helper'

# E4 (#2897): o seguro de uma linha da planilha, lido para as colunas da apólice, e o que falta nele. Dados fictícios.
RSpec.describe Carteira::Trazer::SeguroLido, :aggregate_failures do
  let(:valores) do
    { 'numero' => 'EX-001234', 'seguradora' => 'Seguradora Exemplo S.A.', 'tipo' => 'Automóvel', 'comeca' => '10/03/2026',
      'termina' => '10/03/2027', 'valor' => 'R$ 3.410,00', 'bem' => 'Carro Exemplo 2022' }
  end

  it 'lê a linha inteira para a forma do banco e guarda o ramo como veio' do
    lido = described_class.call(valores)

    expect(lido.atributos).to eq(
      numero: 'EX-001234', numero_chave: 'EX001234', seguradora: 'Seguradora Exemplo S.A.', seguradora_chave: 'seguradoraexemplosa',
      inicio_vigencia: Date.new(2026, 3, 10), fim_vigencia: Date.new(2027, 3, 10), valor_centavos: 341_000, bem: 'Carro Exemplo 2022'
    )
    expect([lido.ramo, lido.motivos, lido.completo?, lido.chave]).to eq(['Automóvel', [], true, %w[seguradoraexemplosa EX001234]])
  end

  it 'começo, valor, bem e ramo podem faltar: o seguro continua inteiro' do
    lido = described_class.call(valores.merge('comeca' => '', 'valor' => '', 'bem' => '', 'tipo' => ''))

    expect(lido.atributos.values_at(:inicio_vigencia, :valor_centavos, :bem)).to eq([nil, nil, nil])
    expect([lido.ramo, lido.completo?]).to eq([nil, true])
  end

  it 'diz o que falta ou veio errado, em códigos que nunca levam o texto da célula' do
    tabela = {
      { 'numero' => '' } => %w[seguro_numero_falta],
      { 'numero' => '---' } => %w[seguro_numero_falta],
      { 'numero' => '1,23457E+15' } => %w[seguro_numero_cientifico],
      { 'numero' => '1.23457e+15' } => %w[seguro_numero_cientifico],
      { 'numero' => 'RE+2024' } => [],
      { 'seguradora' => '' } => %w[seguro_seguradora_falta],
      { 'termina' => '' } => %w[seguro_termina_falta],
      { 'termina' => 'março' } => %w[seguro_termina_invalida],
      { 'comeca' => 'ano passado' } => %w[seguro_comeca_invalida],
      { 'comeca' => '10/03/2027', 'termina' => '10/03/2026' } => %w[seguro_termina_antes],
      { 'valor' => 'a combinar' } => %w[seguro_valor_invalido],
      { 'numero' => '', 'termina' => '', 'valor' => 'x' } => %w[seguro_numero_falta seguro_termina_falta seguro_valor_invalido]
    }

    tabela.each do |mudou, motivos|
      lido = described_class.call(valores.merge(mudou))

      expect([lido.motivos, lido.completo?]).to eq([motivos, motivos.empty?]), mudou.to_s
    end
  end
end
