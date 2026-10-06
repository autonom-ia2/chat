require 'rails_helper'

# #993 (decision of 05/10): every phone the campaign features show is the country code and the
# last 4 digits only.
RSpec.describe CampaignImports::PhoneMask do
  it 'keeps only the country code and the last 4 digits' do
    expect(described_class.mask('+5511987654321')).to eq('+55 •• •••••-4321')
    expect(described_class.mask('11987654321')).to eq('+55 •• •••••-4321')
    expect(described_class.mask('+551187654321')).to eq('+55 •• ••••-4321')
    expect(described_class.mask('11 3456-7890')).to eq('+55 •• ••••-7890')
    expect(described_class.mask('+1 415 555 0100')).to eq('+1 •• ••••-0100')
  end

  it 'shows nothing of short or empty values' do
    expect(described_class.mask('123')).to eq('•••')
    expect(described_class.mask('')).to eq('')
    expect(described_class.mask(nil)).to eq('')
  end

  it 'is the mask of audience rows, error CSVs and WhatsApp API recipients' do
    expect(CampaignImports::PhoneNormalizer.normalize!('11987654321').masked).to eq('+55 •• •••••-4321')
    expect(CampaignImports::PhoneNormalizer.mask_raw('(11) 3456-7890')).to eq('+55 •• ••••-7890')
    expect(WhatsappApiCampaigns::PhonePrivacy.mask('+5521987654321')).to eq('+55 •• •••••-4321')
  end
end
