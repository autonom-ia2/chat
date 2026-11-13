require 'rails_helper'

# E4 (#2897): as linhas da planilha cujo seguro precisa da pessoa. As linhas são as do validador (aqui, só os campos que
# contam). Dados fictícios.
RSpec.describe Carteira::Trazer::ProblemasDeSeguro, :aggregate_failures do
  let(:colunas) do
    Carteira::Trazer::ColunasDeSeguro.new(
      'seguro_numero' => 'Apólice', 'seguro_seguradora' => 'Seguradora', 'seguro_tipo' => 'Ramo', 'seguro_termina' => 'Fim',
      'seguro_comeca' => 'Início', 'seguro_valor' => 'Prêmio', 'seguro_bem' => 'Bem'
    )
  end
  let(:seguro) do
    { 'Apólice' => 'EX-001234', 'Seguradora' => 'Seguradora Exemplo', 'Ramo' => 'Automóvel', 'Início' => '10/03/2026', 'Fim' => '10/03/2027',
      'Prêmio' => '3.410,00', 'Bem' => 'Carro Exemplo 2022' }
  end

  def linha(numero, mudou = {}, telefone: '+5511987650001', erros: [])
    { row_number: numero, normalized_phone: telefone, email: nil, extra_values: seguro.merge(mudou), errors: erros }
  end

  def marcar(linhas)
    [described_class.new(colunas).marcar(linhas), linhas]
  end

  it 'a linha sem o fim da vigência vira problema e continua na lista, para a pessoa ver' do
    repetidas, linhas = marcar([linha(2), linha(3, { 'Apólice' => 'EX-005678', 'Fim' => '' })])

    expect(repetidas).to eq(0)
    expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, %w[seguro_termina_falta]]])
  end

  it 'o número em notação científica vira problema: o Excel trocou os últimos dígitos por zero' do
    _, linhas = marcar([linha(2, { 'Apólice' => '1,23457E+15' })])

    expect(linhas.sole[:errors]).to eq(%w[seguro_numero_cientifico])
  end

  it 'o mesmo número em duas linhas com valores diferentes vira problema na segunda, que guarda qual é a primeira' do
    repetidas, linhas = marcar([linha(2), linha(3, { 'Apólice' => 'ex 001234', 'Prêmio' => '9.999,00' }, telefone: '+5511987650004')])

    expect(repetidas).to eq(0)
    expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, %w[seguro_duplicado]]])
    expect(linhas.last[:outra]).to equal(linhas.first)
  end

  it 'a mesma apólice de pessoas diferentes também é problema: o sistema não escolhe de quem ela é' do
    _, linhas = marcar([linha(2), linha(3, telefone: '+5511987650004')])

    expect(linhas.pluck(:errors)).to eq([[], %w[seguro_duplicado]])
  end

  it 'a linha igual a outra em tudo sai da lista e é contada' do
    repetidas, linhas = marcar([linha(2), linha(3, { 'Apólice' => 'EX 001234', 'Ramo' => 'AUTOMÓVEL ' }), linha(4)])

    expect(repetidas).to eq(2)
    expect(linhas.pluck(:row_number, :errors)).to eq([[2, []]])
  end

  it 'a renovação que mantém o número não é repetida: são dois seguros' do
    repetidas, linhas = marcar([linha(2), linha(3, { 'Início' => '10/03/2027', 'Fim' => '10/03/2028' })])

    expect([repetidas, linhas.pluck(:errors)]).to eq([0, [[], []]])
  end

  it 'a linha que já tinha problema não é comparada com as outras' do
    _, linhas = marcar([linha(2, erros: ['invalid_phone']), linha(3, { 'Prêmio' => '9.999,00' })])

    expect(linhas.pluck(:errors)).to eq([%w[invalid_phone], []])
  end

  it 'diz à tela o tipo e o motivo do problema, o do seguro antes dos outros, e o que só se arruma na planilha' do
    pendencia = described_class.pendencia(%w[invalid_phone seguro_valor_invalido seguro_termina_invalida])

    expect([pendencia.tipo, pendencia.motivo]).to eq(%w[falta_termina data_invalida])
    expect(described_class.pendencia(%w[seguro_duplicado]).to_h).to include(tipo: 'duplicado', motivo: nil)
    expect(described_class.pendencia(%w[invalid_phone])).to be_nil
    expect(%w[falta_termina numero seguradora comeca valor duplicado telefone].map { |tipo| described_class.sem_conserto?(tipo) })
      .to eq([true, true, true, true, true, false, false])
  end
end
