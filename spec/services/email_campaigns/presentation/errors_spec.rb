require 'rails_helper'

RSpec.describe EmailCampaigns::Presentation::Errors do
  it 'exposes supported schema and service failures without replacing them with a generic failure' do
    %w[duplicated_name_header duplicated_email_header missing_email_header schema_not_resolved typesafe_invalid_key
       typesafe_unavailable typesafe_invalid_request].each do |code|
      expect(described_class.import_code(code)).to eq(code)
    end
  end

  it 'never forwards arbitrary storage or provider messages to the product' do
    expect(described_class.import_code('unexpected private error')).to eq('import_failed')
    expect(described_class.import_code(nil)).to be_nil
  end
end
