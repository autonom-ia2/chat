# frozen_string_literal: true

require 'uri'

class Autonomia::Financial::StoreConfiguration
  attr_reader :api_key, :assertion_secret, :namespace, :base_url

  def initialize(env = ENV)
    @api_key = env.fetch('FINANCIAL_STORE_API_KEY', '')
    @assertion_secret = env.fetch('FINANCIAL_STORE_ACTOR_ASSERTION_SECRET', '')
    @namespace = {
      'installationId' => env.fetch('FINANCIAL_STORE_INSTALLATION_ID', ''),
      'productCatalogItemId' => env.fetch('FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID', '')
    }
    @base_url = env.fetch('AUTONOMIA_FINANCIAL_API_BASE_URL', 'https://financial.api-autonomia.com')
    validate_credentials!
    Autonomia::Financial::StoreContract.validate!('namespace', @namespace)
    validate_origin!
  rescue URI::InvalidURIError, Autonomia::Financial::StoreContractError
    raise Autonomia::Financial::StoreClientError.new('STORE_NOT_CONFIGURED', status: 503)
  end

  private

  def validate_credentials!
    valid = [@api_key, @assertion_secret].all? { |value| value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/) }
    valid &&= @assertion_secret.bytesize >= 32 && @assertion_secret != @api_key
    raise Autonomia::Financial::StoreClientError.new('STORE_NOT_CONFIGURED', status: 503) unless valid
  end

  def validate_origin!
    uri = URI.parse(@base_url)
    return if uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && ['', '/'].include?(uri.path)

    raise Autonomia::Financial::StoreClientError.new('STORE_NOT_CONFIGURED', status: 503)
  end
end
