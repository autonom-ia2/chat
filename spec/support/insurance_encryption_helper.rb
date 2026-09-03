# Liga o cofre do ActiveRecord::Encryption com chaves de TESTE dentro de um exemplo. O CI não tem
# ACTIVE_RECORD_ENCRYPTION_*; sem isto o model Autonomia::Insurance::Connection recusa credenciais
# (comportamento correto em produção sem cofre, e testado à parte).
module InsuranceEncryptionHelper
  TEST_KEYS = {
    primary_key: 'insurance-spec-primary-key-0123456789ab',
    deterministic_key: 'insurance-spec-deterministic-key-0123',
    key_derivation_salt: 'insurance-spec-salt-0123456789abcdef'
  }.freeze

  def enable_test_encryption!
    ActiveRecord::Encryption.configure(**TEST_KEYS, support_unencrypted_data: true)
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
  end
end

RSpec.configure do |config|
  config.include InsuranceEncryptionHelper
end
