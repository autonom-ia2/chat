require 'rails_helper'

RSpec.describe CampaignImports::AudienceRowContacts, :aggregate_failures do
  let(:two_numbers) { '(11) 3456-7890 / (11) 3456-7891' }

  it 'reads and masks as before in the classic reading' do
    fields = described_class.new(CampaignImports::ContactReading::CLASSIC).fields('(11) 8765-4321', 'Ana@x.com.br; ana@y.com')

    expect(fields).to include(normalized_phone: nil, email: nil, ninth_digit_added: false)
    expect(fields[:email_masked]).to eq(EmailCampaigns::EmailNormalizer.mask('ana@x.com.br; ana@y.com'))
    expect(described_class.new(CampaignImports::ContactReading::CLASSIC).fields(two_numbers, '')[:raw_phone_masked])
      .to eq(CampaignImports::PhoneNormalizer.mask_raw(two_numbers))
  end

  it 'adds the ninth digit only with legacy mobiles allowed in the customer_base reading' do
    customer_base = CampaignImports::ContactReading::CUSTOMER_BASE

    expect(described_class.new(customer_base).fields('(11) 8765-4321', '')[:errors]).to eq(['invalid_brazilian_mobile_number'])
    expect(described_class.new(customer_base.with_legacy_mobiles(true)).fields('(11) 8765-4321', ''))
      .to include(normalized_phone: '+5511987654321', ninth_digit_added: true, errors: [])
  end

  it 'masks every number and every address of a cell on its own in the customer_base reading' do
    fields = described_class.new(CampaignImports::ContactReading::CUSTOMER_BASE).fields(two_numbers, 'ana@; bia@')

    expect(fields[:raw_phone_masked]).to eq(two_numbers.split(' / ').map { |number| CampaignImports::PhoneNormalizer.mask_raw(number) }.join('; '))
    expect(fields[:email_masked]).to eq('a**@; b**@')
  end
end
