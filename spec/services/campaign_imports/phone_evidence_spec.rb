require 'rails_helper'

RSpec.describe CampaignImports::PhoneEvidence do
  let(:reading) { CampaignImports::ContactReading::CUSTOMER_BASE.with_legacy_mobiles(true) }

  it 'counts legacy mobiles and country codes, never returning a value' do
    values = ['(11) 8765-4321', '11987654321', '+55 21 98765-4321', '+1 917 555 1234', 'Tel: +34 912 345 678', '(11) 3456-7890']

    evidence = described_class.new(values, reading).to_h

    expect(evidence).to eq(complete_brazilian_mobile_count: 2, legacy_mobile_count: 1, country_code_55_count: 1, other_country_code_count: 2)
  end
end
