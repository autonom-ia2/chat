require 'rails_helper'

# Telefone mascarado da página pública do convite (#1190, RA-05): DDD e 4 últimos dígitos, nunca o número inteiro.
RSpec.describe Crm::BookingV2::PhoneMask do
  it 'masks Brazilian mobile and landline numbers keeping area code and last 4 digits' do
    expect(described_class.mask('+5511912345678')).to eq('(11) •••••-5678')
    expect(described_class.mask('+551133334444')).to eq('(11) ••••-4444')
  end

  it 'keeps only the last 4 digits when the national format has no area code in parentheses' do
    expect(described_class.mask('+447911123456')).to eq('••••• ••3456')
  end

  it 'returns nil for blank or invalid numbers' do
    expect(described_class.mask(nil)).to be_nil
    expect(described_class.mask('')).to be_nil
    expect(described_class.mask('+55123')).to be_nil
  end
end
