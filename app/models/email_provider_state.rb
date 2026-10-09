class EmailProviderState < ApplicationRecord
  validates :provider_key, presence: true
  validates :status, inclusion: { in: %w[unknown healthy blocked] }

  def latched?
    blocked || status == 'blocked'
  end
end
