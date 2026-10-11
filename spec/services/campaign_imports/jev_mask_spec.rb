require 'rails_helper'

RSpec.describe CampaignImports::JevMask, :aggregate_failures do
  it 'keeps only the country code and the DDD of a phone visible' do
    expect(described_class.mask('(11) 98765-4321')).to eq('(11) 00000-0000')
    expect(described_class.mask('+55 11 98765-4321')).to eq('+55 11 00000-0000')
    expect(described_class.mask('+1 917-555-1234')).to eq('+1 917-000-0000')
    expect(described_class.mask('1187654321')).to eq('1100000000')
    expect(described_class.mask('011 98765-4321')).to eq('011 00000-0000')
    expect(described_class.mask('917 555 1234')).to eq('917 000 0000')
    expect(described_class.mask('+5511987654321')).to eq('+5511000000000')
  end

  it 'never leaves more than the country code and the area code of a number visible' do
    ['(11) 98765-4321', '+55 11 98765-4321', '5511987654321', 'Tel: (21) 3456-7890', '0055 11 98765 4321', '123.456.789-09'].each do |value|
      visible = described_class.mask(value).count('1-9')
      expect(visible).to be <= 5, "#{value} → #{described_class.mask(value)}"
      expect(described_class.mask(value)).not_to include('98765', '4321', '3456', '789')
    end
  end

  it 'keeps the email domain and masks the local part of every address' do
    expect(described_class.mask('joao@empresa.com.br')).to eq('aaaa@empresa.com.br')
    expect(described_class.mask('Ana.Souza@x.com; bia@y.com.br')).to eq('Aaa.Aaaaa@x.com; aaa@y.com.br')
  end

  it 'leaves values that look like neither alone' do
    expect(described_class.mask('Ana Souza')).to be_nil
    expect(described_class.mask('Rua 7, 120')).to be_nil
  end
end
