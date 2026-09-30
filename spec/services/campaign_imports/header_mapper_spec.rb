require 'rails_helper'

RSpec.describe CampaignImports::HeaderMapper do
  it 'maps accepted Portuguese and English aliases' do
    result = described_class.new(['Nome Completo', 'Whatsapp']).perform

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(name: 0, phone_number: 1)
  end

  it 'reports missing logical columns in phone mode' do
    result = described_class.new(['email']).perform

    expect(result.errors).to include('missing_name_header', 'missing_phone_number_header')
  end

  it 'treats recipient name as optional in email mode' do
    result = described_class.new(['E-mail'], mode: :email).perform

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(email: 0)
  end

  it 'maps email-mode headers containing accepted email aliases' do
    result = described_class.new(['Corretora', 'Nome', 'Email Tratado'], mode: :email).perform

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(name: 1, email: 2)
    expect(result.extra_columns).to eq('corretora' => 0)
  end

  it 'does not mistake an email-address value for an email header' do
    result = described_class.new(['Ana', 'ana@email.com'], mode: :email).perform

    expect(result.errors).to contain_exactly('missing_email_header')
    expect(result.mapping).to be_empty
  end

  it 'reports duplicate email headers when multiple email-mode columns contain email aliases' do
    result = described_class.new(['Nome', 'Email Tratado', 'E-mail Principal'], mode: :email).perform

    expect(result.errors).to include('duplicated_email_header')
  end

  it 'builds explicit AI mappings while keeping every other column as custom data' do
    result = described_class.new(['Segurado', 'Mail Principal', 'Corretora', 'UF'], mode: :email).perform(
      explicit_mapping: { name: 0, email: 1 }
    )

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(name: 0, email: 1)
    expect(result.extra_columns).to eq('corretora' => 2, 'uf' => 3)
  end
end
