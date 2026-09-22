require 'rails_helper'

RSpec.describe Chatwoot, '.mfa_enabled?' do
  let(:chaves) do
    {
      'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => 'primaria',
      'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY' => 'deterministica',
      'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT' => 'sal'
    }
  end

  it 'fica ligado com as chaves de criptografia e sem o login único automático' do
    with_modified_env(chaves.merge('AUTONOMIA_SSO_AUTO_REDIRECT' => nil)) do
      expect(described_class.mfa_enabled?).to be(true)
    end
  end

  it 'fica desligado quando a entrada é pelo login único automático' do
    with_modified_env(chaves.merge('AUTONOMIA_SSO_AUTO_REDIRECT' => 'true')) do
      expect(described_class.mfa_enabled?).to be(false)
    end
  end

  it 'fica desligado sem as chaves de criptografia' do
    with_modified_env('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => nil, 'AUTONOMIA_SSO_AUTO_REDIRECT' => nil) do
      expect(described_class.mfa_enabled?).to be(false)
    end
  end
end
