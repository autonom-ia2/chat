require 'rails_helper'

RSpec.describe Crm::MetaAdsConnection do
  let(:account) { create(:account) }

  it 'recusa gravar o token sem o cofre de criptografia configurado' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    connection = described_class.new(account: account, access_token: MetaAdsHelpers::TEST_TOKEN)

    expect(connection).not_to be_valid
    expect(connection.errors[:base].join).to include('ACTIVE_RECORD_ENCRYPTION')
  end

  it 'guarda o token cifrado: a coluna crua no banco não contém o token' do
    connection = create_meta_ads_connection(account)

    raw = described_class.connection.select_value(
      described_class.sanitize_sql_array(['SELECT access_token FROM crm_meta_ads_connections WHERE id = ?', connection.id])
    )

    expect(raw).to be_present
    expect(raw).not_to include(MetaAdsHelpers::TEST_TOKEN)
    expect(raw).not_to include(MetaAdsHelpers::TEST_TOKEN.first(12))
    expect(described_class.find(connection.id).access_token).to eq(MetaAdsHelpers::TEST_TOKEN)
  end

  it 'permite uma credencial por conta' do
    create_meta_ads_connection(account)

    expect { described_class.create!(account: account, access_token: 'outro-token-qualquer') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'payload público nunca leva o token' do
    connection = create_meta_ads_connection(account)

    expect(connection.public_payload.keys).to contain_exactly(:configured, :status, :last_checked_at, :last_error)
    expect(connection.public_payload.to_json).not_to include(MetaAdsHelpers::TEST_TOKEN.first(8))
  end

  it 'marca invalid com erro curto e limpo de trechos com cara de segredo' do
    connection = create_meta_ads_connection(account)

    connection.mark_invalid!("Token #{MetaAdsHelpers::TEST_TOKEN} expirou #{'x' * 400}")

    expect(connection.reload.status).to eq('invalid')
    expect(connection.last_error).not_to include(MetaAdsHelpers::TEST_TOKEN)
    expect(connection.last_error.length).to be <= 255
  end
end
