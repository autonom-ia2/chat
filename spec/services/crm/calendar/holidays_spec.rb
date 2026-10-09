require 'rails_helper'

# Feriados nacionais do Brasil (#1195, J3-A13): fixos e móveis, conferidos contra o calendário oficial de 2026 e 2027.
RSpec.describe Crm::Calendar::Holidays do
  it 'calcula o domingo de Páscoa de anos conhecidos' do
    expect(described_class.easter(2024)).to eq(Date.new(2024, 3, 31))
    expect(described_class.easter(2025)).to eq(Date.new(2025, 4, 20))
    expect(described_class.easter(2026)).to eq(Date.new(2026, 4, 5))
    expect(described_class.easter(2027)).to eq(Date.new(2027, 3, 28))
    expect(described_class.easter(2038)).to eq(Date.new(2038, 4, 25))
  end

  it 'calcula a Páscoa de 2026 a 2030 como o calendário oficial' do
    expect((2026..2030).map { |year| described_class.easter(year) }).to eq(
      [Date.new(2026, 4, 5), Date.new(2027, 3, 28), Date.new(2028, 4, 16), Date.new(2029, 4, 1), Date.new(2030, 4, 21)]
    )
  end

  it 'lista os feriados de 2026 em ordem de data' do
    expect(described_class.for_year(2026)).to eq(
      Date.new(2026, 1, 1) => 'new_year',
      Date.new(2026, 2, 16) => 'carnival_monday',
      Date.new(2026, 2, 17) => 'carnival_tuesday',
      Date.new(2026, 4, 3) => 'good_friday',
      Date.new(2026, 4, 21) => 'tiradentes',
      Date.new(2026, 5, 1) => 'labour_day',
      Date.new(2026, 6, 4) => 'corpus_christi',
      Date.new(2026, 9, 7) => 'independence_day',
      Date.new(2026, 10, 12) => 'our_lady_aparecida',
      Date.new(2026, 11, 2) => 'all_souls_day',
      Date.new(2026, 11, 15) => 'republic_day',
      Date.new(2026, 11, 20) => 'black_consciousness_day',
      Date.new(2026, 12, 25) => 'christmas'
    )
  end

  it 'acerta os móveis de 2027' do
    holidays = described_class.for_year(2027)

    expect(holidays.select { |_date, name| described_class::MOVABLE.value?(name) }).to eq(
      Date.new(2027, 2, 8) => 'carnival_monday',
      Date.new(2027, 2, 9) => 'carnival_tuesday',
      Date.new(2027, 3, 26) => 'good_friday',
      Date.new(2027, 5, 27) => 'corpus_christi'
    )
    expect(holidays.size).to eq(13)
  end

  it 'acerta Carnaval em ano bissexto (2028) e Sexta-feira Santa e Corpus Christi de 2029 e 2030' do
    expect(described_class.name_for(Date.new(2028, 2, 28))).to eq('carnival_monday')
    expect(described_class.name_for(Date.new(2028, 2, 29))).to eq('carnival_tuesday')
    expect(described_class.name_for(Date.new(2029, 3, 30))).to eq('good_friday')
    expect(described_class.name_for(Date.new(2029, 5, 31))).to eq('corpus_christi')
    expect(described_class.name_for(Date.new(2030, 4, 19))).to eq('good_friday')
    expect(described_class.name_for(Date.new(2030, 6, 20))).to eq('corpus_christi')
    expect(described_class.name_for(Date.new(2030, 4, 21))).to eq('tiradentes') # Páscoa no mesmo dia
  end

  it 'responde por data, sem confundir a véspera nem o dia seguinte' do
    expect(described_class.holiday?(Date.new(2026, 10, 12))).to be(true)
    expect(described_class.name_for(Date.new(2027, 3, 26))).to eq('good_friday')
    expect(described_class.holiday?(Date.new(2026, 10, 13))).to be(false)
    expect(described_class.holiday?(Date.new(2026, 2, 18))).to be(false) # Quarta de Cinzas não fecha
    expect(described_class.holiday?(Date.new(2026, 4, 5))).to be(false) # a própria Páscoa é domingo comum aqui
  end
end
