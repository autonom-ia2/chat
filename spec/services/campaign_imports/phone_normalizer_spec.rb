require 'rails_helper'

RSpec.describe CampaignImports::PhoneNormalizer do
  it 'normalizes Brazilian mobile phones to E.164' do
    expect(described_class.normalize!('11987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('5511987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('+5511987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('(11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'drops the long-distance trunk 0 and the international 00 prefix' do
    expect(described_class.normalize!('011 98765-4321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('0055 11 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'restores the ninth digit of a legacy eight-digit mobile' do
    expect(described_class.normalize!('(11) 8765-4321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('551187654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('021 6543-2109').phone_number).to eq('+5521965432109')
  end

  it 'rejects Brazilian landlines' do
    expect { described_class.normalize!('(11) 3456-4321') }.to raise_error(
      described_class::Error,
      'invalid_brazilian_mobile_number'
    )
    expect { described_class.normalize!('551134564321') }.to raise_error(described_class::Error, 'invalid_brazilian_mobile_number')
  end
end
