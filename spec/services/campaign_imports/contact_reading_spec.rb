require 'rails_helper'

RSpec.describe CampaignImports::ContactReading do
  let(:account) { create(:account) }

  it 'is the classic reading unless the account has customer_base' do
    expect(described_class.for(account)).to be(described_class::CLASSIC)

    account.enable_features!('customer_base')

    expect(described_class.for(account.reload)).to be(described_class::CUSTOMER_BASE)
  end

  it 'reads cells exactly as before in the classic reading' do
    reading = described_class::CLASSIC

    expect(reading.phone?('(11) 8765-4321')).to be(false)
    expect(reading.email?('ana@x.com.br; ana@y.com')).to be(false)
    expect(reading.phone('(11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'reads legacy mobiles and cells with several values in the customer_base reading' do
    reading = described_class::CUSTOMER_BASE

    expect(reading.phone('(11) 8765-4321').phone_number).to eq('+5511987654321')
    expect(reading.email('Ana@x.com.br; ana@y.com').email).to eq('ana@x.com.br')
    expect(reading.phone?('(11) 3456-7890 / (11) 98765-4321')).to be(true)
    expect(reading.phone?('917 555 1234')).to be(false)
    expect(reading.contact?('')).to be(false)
  end
end
