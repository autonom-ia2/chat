require 'rails_helper'

RSpec.describe Autonomia::Insurance::Connection do
  let(:account) { create(:account) }

  it 'refuses to store credentials when the encryption vault is not configured' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    connection = described_class.new(account: account, username: 'a@b.com', password: 'x')

    expect(connection).not_to be_valid
    expect(connection.errors[:base].join).to include('ACTIVE_RECORD_ENCRYPTION')
  end

  it 'stores credentials, masks the login and keeps one connection per account/provider' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'corretora@exemplo.com.br', password: 'x')

    expect(connection.username_hint).to eq('co*******@exemplo.com.br')
    expect(connection.public_payload.keys).not_to include(:password, :username)
    expect(connection.public_payload.to_json).not_to include('corretora@exemplo.com.br')
    expect { described_class.create!(account: account, username: 'o@b.com', password: 'y') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'allows an empty (not_configured) record without the vault' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    expect(described_class.new(account: account)).to be_valid
  end
end
