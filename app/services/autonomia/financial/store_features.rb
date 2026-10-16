# frozen_string_literal: true

class Autonomia::Financial::StoreFeatures
  PILOT_KEY = 'prospecting'
  KEYS = %w[prospecting email_campaigns whatsapp_api_campaigns].freeze

  def self.target!(key)
    raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403) unless KEYS.include?(key)

    { 'type' => 'feature', 'featureKey' => key }
  end
end
