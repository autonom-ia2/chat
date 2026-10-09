# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Proposed E0 API. No controllers/jobs call this client until Financial ships the scoped contract.
class Autonomia::Financial::StoreClient < Autonomia::Financial::Client
  STORE_PATH = '/financial/internal/store'.freeze
  RESERVATIONS_PATH = '/financial/internal/usage-reservations'.freeze
  ERROR_CODES = %w[IDEMPOTENCY_CONFLICT USAGE_RESERVATION_NOT_FOUND USAGE_LIMIT_EXCEEDED FORBIDDEN UNAUTHORIZED].freeze

  def initialize(authorization_token:, installation_api_key:, namespace:, buyer_subject:, base_url:)
    super(authorization_token: authorization_token)
    credentials = [authorization_token, installation_api_key]
    raise ArgumentError, 'Financial credentials are required.' if credentials.any? { |value| !value.is_a?(String) || value.strip.empty? }
    raise ArgumentError, 'Invalid Financial credentials.' if credentials.any? { |value| value.match?(/[\r\n]/) }

    @namespace = Autonomia::Financial::StoreContract.validate!('namespace', namespace).dup.freeze
    @buyer_subject = Autonomia::Financial::StoreContract.validate!('identifier', buyer_subject)
    @installation_api_key = installation_api_key
    @base_uri = URI.parse(base_url)
    raise ArgumentError, 'Financial store requires an HTTPS origin.' unless https_origin?
  end

  def service_subscription!(subscription_id)
    Autonomia::Financial::StoreContract.validate!('uuid', subscription_id)
    payload = request_json(:get, "#{STORE_PATH}/service-subscriptions/#{subscription_id}", 'serviceSubscription')
    validate_namespace!(payload.fetch('namespace'))
    matches_buyer = payload.fetch('buyer').fetch('cognitoSub') == @buyer_subject
    raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH') unless payload.fetch('id') == subscription_id && matches_buyer

    payload
  end

  def catalog!(page: 1, page_size: 20)
    pagination = { 'page' => page, 'pageSize' => page_size, 'totalItems' => 0, 'totalPages' => 0 }
    Autonomia::Financial::StoreContract.validate!('pagination', pagination)
    payload = request_json(:get, "#{STORE_PATH}/catalog?page=#{page}&pageSize=#{page_size}", 'catalogResponse')
    validate_namespace!(payload.fetch('namespace'))
    payload.fetch('data').each do |item|
      target = item.fetch('target')
      next unless target.fetch('type') == 'agent'
      next if target.fetch('installationId') == @namespace.fetch('installationId')

      raise Autonomia::Financial::StoreClientError.new('RESPONSE_SCOPE_MISMATCH')
    end
    payload
  end

  def checkout!(payload, idempotency_key:)
    Autonomia::Financial::StoreContract.validate!('identifier', idempotency_key)
    Autonomia::Financial::StoreContract.validate!('checkoutRequest', payload)
    request_json(:post, "#{STORE_PATH}/checkout-sessions", 'checkoutResponse', payload: payload, idempotency_key: idempotency_key)
  end

  def reserve!(payload)
    Autonomia::Financial::StoreContract.validate!('reserveRequest', payload)
    response = reservation_request(:post, RESERVATIONS_PATH, payload)
    reservation = response.fetch('reservation')
    fields = %w[serviceSubscriptionId metricKey quantity resourceRef]
    matches_target = fields.all? { |key| reservation[key] == payload[key] }
    raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown') unless matches_target

    response
  end

  def reservation!(reservation_id)
    Autonomia::Financial::StoreContract.validate!('uuid', reservation_id)
    response = reservation_request(:get, "#{RESERVATIONS_PATH}/#{reservation_id}")
    validate_reservation_id!(response, reservation_id, outcome: 'failure')
    response
  end

  def commit!(reservation_id, payload)
    settle!(reservation_id, payload, 'commit', 'commitRequest')
  end

  def release!(reservation_id, payload)
    settle!(reservation_id, payload, 'release', 'releaseRequest')
  end

  private

  def https_origin?
    @base_uri.is_a?(URI::HTTPS) && @base_uri.host && @base_uri.userinfo.nil? &&
      @base_uri.query.nil? && @base_uri.fragment.nil? && ['', '/'].include?(@base_uri.path)
  end

  def settle!(reservation_id, payload, action, schema)
    Autonomia::Financial::StoreContract.validate!('uuid', reservation_id)
    Autonomia::Financial::StoreContract.validate!(schema, payload)
    response = reservation_request(:post, "#{RESERVATIONS_PATH}/#{reservation_id}/#{action}", payload)
    validate_reservation_id!(response, reservation_id, outcome: 'unknown')
    response
  end

  def reservation_request(method, path, payload = nil)
    response = request_json(method, path, 'reservationResponse', payload: payload)
    validate_namespace!(response.fetch('reservation').fetch('namespace'), outcome: method == :post ? 'unknown' : 'failure')
    response
  end

  def validate_namespace!(namespace, outcome: 'failure')
    return if namespace == @namespace

    raise Autonomia::Financial::StoreClientError.new('RESPONSE_SCOPE_MISMATCH', outcome: outcome)
  end

  def validate_reservation_id!(response, reservation_id, outcome:)
    return if response.fetch('reservation').fetch('id') == reservation_id

    raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: outcome)
  end

  def request_json(method, path, schema, payload: nil, idempotency_key: nil)
    uri = URI.join(@base_uri, path)
    request = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    request['Accept'] = 'application/json'
    request['Authorization'] = "Bearer #{authorization_token}"
    request['X-Api-Key'] = @installation_api_key
    request['Idempotency-Key'] = idempotency_key if idempotency_key
    if payload
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(payload)
    end
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15,
                              write_timeout: 5, max_retries: 0) { |http| http.request(request) }
    parse_response(response, schema, method)
  rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
    raise Autonomia::Financial::StoreClientError.new('TRANSPORT_ERROR', outcome: method == :post ? 'unknown' : 'failure')
  end

  def parse_response(response, schema, method)
    payload = JSON.parse(response.body.to_s)
    raise_response_error(response, payload, method) unless response.is_a?(Net::HTTPSuccess)
    Autonomia::Financial::StoreContract.validate!(schema, payload)
  rescue JSON::ParserError, Autonomia::Financial::StoreContractError
    raise Autonomia::Financial::StoreClientError.new('INVALID_RESPONSE', outcome: method == :post ? 'unknown' : 'failure')
  end

  def raise_response_error(response, payload, method)
    code = payload.is_a?(Hash) && payload.dig('error').is_a?(Hash) ? payload.dig('error', 'code') : nil
    code = 'UPSTREAM_REJECTED' unless ERROR_CODES.include?(code)
    status = response.code.to_i
    outcome = method == :post && status >= 500 ? 'unknown' : 'failure'
    raise Autonomia::Financial::StoreClientError.new(code, status: status, outcome: outcome)
  end
end
