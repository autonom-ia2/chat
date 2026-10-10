require 'rails_helper'

RSpec.describe AiProviderCredential do
  it 'refuses to store an API key when Active Record Encryption is unavailable' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    credential = described_class.new(provider: 'typesafe', api_key: 'secret')

    expect(credential).not_to be_valid
    expect(credential.errors[:base].join).to include('ACTIVE_RECORD_ENCRYPTION')
  end

  it 'encrypts the TypeSafe API key at rest and keeps one credential per provider' do
    enable_test_encryption!
    credential = described_class.create!(provider: 'typesafe', api_key: 'ts_secret_value')
    stored = described_class.connection.select_value(
      "SELECT api_key FROM ai_provider_credentials WHERE id = #{credential.id.to_i}"
    )

    expect(stored).not_to eq('ts_secret_value')
    expect(credential.reload.api_key).to eq('ts_secret_value')
    expect { described_class.create!(provider: 'typesafe', api_key: 'other') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
