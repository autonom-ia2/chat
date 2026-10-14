# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# The canonical subject is verified by Identity; local user IDs are never substituted.
class Autonomia::Financial::StoreIdentity
  def self.subject!(authorization_token, endpoint: ENV.fetch('AUTONOMIA_AUTH_USER_ENDPOINT', 'https://auth.api-autonomia.com/me'))
    response = fetch_response(authorization_token, endpoint_uri(endpoint))
    payload = JSON.parse(response.body.to_s)
    subject = payload.is_a?(Hash) && payload['user'].is_a?(Hash) ? payload['user']['cognitoSub'] : nil
    Autonomia::Financial::StoreContract.validate!('identifier', subject)
  rescue URI::InvalidURIError, JSON::ParserError, Autonomia::Financial::StoreContractError,
         Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
         Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    raise Autonomia::Financial::StoreClientError.new('IDENTITY_UNAVAILABLE', status: 503)
  end

  def self.endpoint_uri(endpoint)
    uri = URI.parse(endpoint)
    unless uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path == '/me'
      raise Autonomia::Financial::StoreClientError.new('STORE_NOT_CONFIGURED', status: 503)
    end

    uri
  end
  private_class_method :endpoint_uri

  def self.fetch_response(authorization_token, uri)
    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/json'
    request['Authorization'] = "Bearer #{authorization_token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 5, max_retries: 0) do |http|
      http.request(request)
    end
    raise Autonomia::Financial::StoreClientError.new('UNAUTHORIZED', status: 401) if response.code.to_i == 401
    raise Autonomia::Financial::StoreClientError.new('IDENTITY_UNAVAILABLE', status: 503) unless response.is_a?(Net::HTTPSuccess)

    response
  end
  private_class_method :fetch_response
end
