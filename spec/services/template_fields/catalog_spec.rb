require 'rails_helper'

RSpec.describe TemplateFields::Catalog do
  it 'gives every field a type of the catalog and a plain label in English and Portuguese' do
    described_class::FIELDS.each do |key, type|
      expect(described_class::TYPES).to include(type)
      expect(described_class.label(key, locale: :pt_BR)).not_to include('translation missing')
      expect(described_class.label(key, locale: :en)).not_to include('translation missing')
    end
    expect(described_class.label('cliente.primeiro_nome', locale: :pt_BR)).to eq('Primeiro nome do cliente')
    expect(described_class.type_label('moeda', locale: :pt_BR)).to eq('Valor em dinheiro')
  end

  it 'reads a spreadsheet column as publico.<header>, typed by the column types' do
    expect(described_class.known?('publico.Vencimento')).to be(true)
    expect(described_class.known?('publico.')).to be(false)
    expect(described_class.label('publico.Data de vencimento')).to eq('Data de vencimento')
    expect(described_class.type('publico.Vencimento', column_types: { 'Vencimento' => 'data' })).to eq('data')
    expect(described_class.type('publico.Obs', column_types: { 'Obs' => nil })).to eq('texto')
    expect(described_class.type('negocio.valor')).to eq('moeda')
    expect(described_class.type('outra.coisa')).to be_nil
  end

  it 'knows what an audience campaign can fill' do
    filled = %w[cliente.primeiro_nome empresa_cliente.nome minha_empresa.site publico.Vencimento]
    not_filled = %w[negocio.valor horario.data_hora atendente.nome fixo cliente.inventado]

    expect(filled.map { |key| described_class.in_audience?(key) }.uniq).to eq([true])
    expect(not_filled.map { |key| described_class.in_audience?(key) }.uniq).to eq([false])
  end
end
