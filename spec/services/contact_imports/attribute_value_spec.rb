require 'rails_helper'

# #1006: a cell becomes the value of a typed contact attribute, or is left out.
RSpec.describe ContactImports::AttributeValue, :aggregate_failures do
  def definition(type, values: [], regex: nil)
    CustomAttributeDefinition.new(attribute_display_type: type, attribute_values: values, regex_pattern: regex)
  end

  def cast(type, raw, **)
    described_class.new(definition(type, **)).cast(raw)
  end

  it 'converts numbers written the Brazilian way' do
    expect(cast('number', '1.234,56')).to eq(1234.56)
    expect(cast('currency', 'R$ 10')).to eq(10)
    expect(cast('percent', '15%')).to eq(15)
    expect(cast('number', '10.5')).to eq(10.5)
    expect(cast('number', 'dez')).to eq(:invalid)
  end

  it 'converts dates from ISO, dd/mm/yyyy and Excel day numbers' do
    expect(cast('date', '2026-03-15')).to eq('2026-03-15')
    expect(cast('date', '15/03/1990')).to eq('1990-03-15')
    expect(cast('date', '45366')).to eq('2024-03-15')
    expect(cast('date', 'amanhã')).to eq(:invalid)
    expect(cast('date', '31/02/2026')).to eq(:invalid)
  end

  it 'converts checkboxes, lists and links' do
    expect(cast('checkbox', 'Sim')).to be(true)
    expect(cast('checkbox', '0')).to be(false)
    expect(cast('checkbox', 'talvez')).to eq(:invalid)
    expect(cast('list', 'ouro', values: %w[Ouro Prata])).to eq('Ouro')
    expect(cast('list', 'Bronze', values: %w[Ouro Prata])).to eq(:invalid)
    expect(cast('link', 'https://alfa.com.br')).to eq('https://alfa.com.br')
    expect(cast('link', 'alfa.com.br')).to eq(:invalid)
  end

  it 'keeps text as written and leaves out blank cells' do
    expect(cast('text', ' Ouro ')).to eq('Ouro')
    expect(cast('date', '  ')).to eq(:invalid)
  end
end
