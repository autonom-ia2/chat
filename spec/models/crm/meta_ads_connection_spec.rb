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

    expect(connection.public_payload.keys).to contain_exactly(:configured, :status, :mode, :last_checked_at, :last_error, :verified_at,
                                                              :destinations, :ad_account, :pixel)
    expect(connection.public_payload.to_json).not_to include(MetaAdsHelpers::TEST_TOKEN.first(8))
  end

  it 'marca invalid com erro curto e limpo de trechos com cara de segredo' do
    connection = create_meta_ads_connection(account)

    connection.mark_invalid!("Token #{MetaAdsHelpers::TEST_TOKEN} expirou #{'x' * 400}")

    expect(connection.reload.status).to eq('invalid')
    expect(connection.last_error).not_to include(MetaAdsHelpers::TEST_TOKEN)
    expect(connection.last_error.length).to be <= 255
  end

  context 'when in partner mode (#1047)' do
    it 'vale sem token próprio e lê com o token da plataforma' do
      enable_test_encryption!
      AiProviderCredential.create!(provider: 'meta_ads', api_key: 'EAAGplataforma123')
      connection = described_class.create!(account: account, mode: 'partner', ad_account_id: '2196424464528988')

      expect(connection.access_token).to be_nil
      expect(connection.read_token).to eq('EAAGplataforma123')
    end

    it 'modo token continua exigindo token' do
      expect(described_class.new(account: account, mode: 'token')).not_to be_valid
    end

    it 'uma conta de anúncios lida pela plataforma é de uma conta só' do
      described_class.create!(account: account, mode: 'partner', ad_account_id: '2196424464528988')

      duplicate = described_class.new(account: create(:account), mode: 'partner', ad_account_id: '2196424464528988')
      expect(duplicate).not_to be_valid
    end

    it 'erro do token da plataforma guarda o motivo mas não deixa a conta inválida' do
      connection = described_class.create!(account: account, mode: 'partner', ad_account_id: '1')

      connection.mark_invalid!('Error validating access token')

      expect(connection.reload).to have_attributes(status: 'active', last_error: 'platform_token_rejected')
    end
  end
end
