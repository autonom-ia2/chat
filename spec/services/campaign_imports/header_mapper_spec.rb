require 'rails_helper'

RSpec.describe CampaignImports::HeaderMapper do
  it 'maps accepted Portuguese and English aliases' do
    result = described_class.new(['Nome Completo', 'Whatsapp']).perform

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(name: 0, phone_number: 1)
  end

  it 'reports missing logical columns' do
    result = described_class.new(['email']).perform

    expect(result.errors).to include('missing_name_header', 'missing_phone_number_header')
  end

  it 'maps email-mode headers containing accepted email aliases' do
    result = described_class.new(['Corretora', 'Nome', 'Email Tratado'], mode: :email).perform

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(name: 1, email: 2)
    expect(result.extra_columns).to eq('corretora' => 0)
  end

  it 'reports duplicate email headers when multiple email-mode columns contain email aliases' do
    result = described_class.new(['Nome', 'Email Tratado', 'E-mail Principal'], mode: :email).perform

    expect(result.errors).to include('duplicated_email_header')
  end
end
