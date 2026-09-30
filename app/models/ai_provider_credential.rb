class AiProviderCredential < ApplicationRecord
  PROVIDERS = %w[typesafe].freeze

  encrypts :api_key

  validates :provider, presence: true, inclusion: { in: PROVIDERS }, uniqueness: true
  validates :api_key, presence: true
  validate :api_key_requires_encryption

  def self.for(provider)
    find_by(provider: provider)
  end

  private

  def api_key_requires_encryption
    return if api_key.blank? || Chatwoot.encryption_configured?

    errors.add(:base, 'ACTIVE_RECORD_ENCRYPTION must be configured before storing AI provider credentials')
  end
end
