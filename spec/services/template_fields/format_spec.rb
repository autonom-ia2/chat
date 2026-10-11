require 'rails_helper'

RSpec.describe TemplateFields::Format do
  it 'writes money in reais from cents, the pt-BR way' do
    expect(described_class.money_cents(125_000)).to eq('R$ 1.250,00')
    expect(described_class.money_cents(5)).to eq('R$ 0,05')
    expect(described_class.money_cents(123_456_789)).to eq('R$ 1.234.567,89')
    expect(described_class.money_cents(1000, 'usd')).to eq('USD 10,00')
    expect(described_class.money_cents(nil)).to be_nil
  end

  it 'writes dates and times in the given time zone' do
    moment = Time.utc(2026, 10, 15, 1, 30)
    zone = ActiveSupport::TimeZone['America/Sao_Paulo']

    expect(described_class.date(moment, zone)).to eq('14/10/2026')
    expect(described_class.time(moment, zone)).to eq('22:30')
    expect(described_class.date(moment, ActiveSupport::TimeZone['UTC'])).to eq('15/10/2026')
    expect(described_class.date(Date.new(2026, 10, 14), zone)).to eq('14/10/2026')
  end

  it 'uses the account time zone, São Paulo when it has none' do
    account = create(:account)
    expect(described_class.account_zone(account).name).to eq('America/Sao_Paulo')

    account.update!(reporting_timezone: 'America/Manaus')
    expect(described_class.account_zone(account).name).to eq('America/Manaus')
  end

  describe '.audience_value' do
    it 'formats the machine forms the reader produces' do
      expect(described_class.audience_value('2026-10-14', 'data')).to eq('14/10/2026')
      expect(described_class.audience_value('2026-10-14 15:00', 'data')).to eq('14/10/2026 15:00')
      expect(described_class.audience_value('1234.5', 'moeda')).to eq('R$ 1.234,50')
      expect(described_class.audience_value('1234.5599999999999', 'moeda')).to eq('R$ 1.234,56')
      expect(described_class.audience_value('80', 'moeda')).to eq('R$ 80,00')
      expect(described_class.audience_value('-80', 'moeda')).to eq('-R$ 80,00')
    end

    it 'keeps what the person wrote her own way' do
      expect(described_class.audience_value('10/2026', 'data')).to eq('10/2026')
      expect(described_class.audience_value('2026-02-30', 'data')).to eq('2026-02-30')
      expect(described_class.audience_value('R$ 1.234,50', 'moeda')).to eq('R$ 1.234,50')
      expect(%w[1.234 1.234.567].map { |text| described_class.audience_value(text, 'moeda') }).to eq(%w[1.234 1.234.567])
      expect(described_class.audience_value('2026-10-14', nil)).to eq('2026-10-14')
      expect(described_class.audience_value("  linha\n  dois ", 'texto')).to eq('linha dois')
      expect(described_class.audience_value('  ', 'texto')).to be_nil
    end
  end
end
