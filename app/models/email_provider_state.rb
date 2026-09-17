class EmailProviderState < ApplicationRecord
  validates :provider_key, presence: true
  validates :status, inclusion: { in: %w[unknown healthy blocked] }

  def self.for_provider(provider_key)
    find_by(provider_key: provider_key) || create_or_find_by!(provider_key: provider_key)
  end

  def latched?
    blocked || status == 'blocked'
  end
end
