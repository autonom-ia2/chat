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
end
