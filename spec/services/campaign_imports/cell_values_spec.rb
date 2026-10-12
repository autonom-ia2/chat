require 'rails_helper'

RSpec.describe CampaignImports::CellValues do
  def phone(value)
    described_class.first_valid(value, CampaignImports::PhoneNormalizer::Error) { |part| CampaignImports::PhoneNormalizer.normalize!(part) }
  end

  it 'keeps a single value as the normalizer reads it' do
    expect(phone('(11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'takes the mobile when the cell also holds a landline' do
    expect(phone('(11) 3456-7890 / (11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'raises the error of the whole cell when no part is valid' do
    expect { phone('(11) 3456-7890, (11) 3456-7891') }
      .to raise_error(CampaignImports::PhoneNormalizer::Error, 'invalid_brazilian_mobile_number')
  end

  it 'masks every address of the cell' do
    expect(described_class.masked_emails('Ana@X.com.br; bia@y.com')).to eq('a**@x.com.br; b**@y.com')
    expect(described_class.masked_emails('ana@x.com.br')).to eq('a**@x.com.br')
  end

  describe '.excel_serial' do
    it 'turns a date serial into an ISO date, ignoring the hour' do
      expect(described_class.excel_serial('46309', :date)).to eq('2026-10-14')
      expect(described_class.excel_serial('46309.75', :date)).to eq('2026-10-14')
    end

    it 'turns a time fraction into hours and minutes' do
      expect(described_class.excel_serial('0.625', :time)).to eq('15:00')
      expect(described_class.excel_serial('46309.5', :datetime)).to eq('2026-10-14 12:00')
    end

    it 'rounds to the minute and rolls 23:59:59.9 over to the next day' do
      expect(described_class.excel_serial('46309.99999', :datetime)).to eq('2026-10-15 00:00')
    end

    it 'counts from 1904 when the workbook says so' do
      expect(described_class.excel_serial('44847', :date, date1904: true)).to eq('2026-10-14')
    end

    it 'keeps the seconds when the format shows them' do
      expect(described_class.excel_serial('0.62535', :time)).to eq('15:01')
      expect(described_class.excel_serial('0.62535', :time_seconds)).to eq('15:00:30')
      expect(described_class.excel_serial('46309.62535', :datetime_seconds)).to eq('2026-10-14 15:00:30')
    end

    it 'keeps what is not a number between 0 and the last Excel day' do
      expect(described_class.excel_serial('2958465', :date)).to eq('9999-12-31')
      expect(described_class.excel_serial('2958466', :date)).to eq('2958466')
      expect(described_class.excel_serial('1e300', :date)).to eq('1e300')
    end

    it 'keeps what is not a non-negative number' do
      expect(described_class.excel_serial('14/10/2026', :date)).to eq('14/10/2026')
      expect(described_class.excel_serial('', :date)).to eq('')
      expect(described_class.excel_serial('-3', :date)).to eq('-3')
      expect(described_class.excel_serial('46309', :currency)).to eq('46309')
    end
  end
end
