require 'rails_helper'

RSpec.describe CampaignImports::CellValues do
  it 'keeps a single value as the normalizer reads it' do
    expect(described_class.normalize!(CampaignImports::PhoneNormalizer, '(11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'takes the first valid email of a cell with several' do
    expect(described_class.normalize!(EmailCampaigns::EmailNormalizer, 'Ana@X.com.br; ana@y.com').email).to eq('ana@x.com.br')
  end

  it 'takes the mobile when the cell also holds a landline' do
    result = described_class.normalize!(CampaignImports::PhoneNormalizer, '(11) 3456-7890 / (11) 98765-4321')

    expect(result.phone_number).to eq('+5511987654321')
  end

  it 'lets the column profile count a cell with several values' do
    expect(CampaignImports::ContactValues.email?('ana@x.com.br; ana@y.com')).to be(true)
    expect(CampaignImports::ContactValues.phone?('(11) 98765-4321 / (11) 3456-7890')).to be(true)
  end

  it 'raises the error of the whole cell when no part is valid' do
    expect { described_class.normalize!(CampaignImports::PhoneNormalizer, '(11) 3456-7890, (11) 3456-7891') }
      .to raise_error(CampaignImports::PhoneNormalizer::Error, 'invalid_brazilian_mobile_number')
  end
end
