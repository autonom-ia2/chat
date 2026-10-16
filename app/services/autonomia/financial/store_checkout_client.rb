# frozen_string_literal: true

class Autonomia::Financial::StoreCheckoutClient < Autonomia::Financial::StorePublicationClient
  USAGE_PATH = "#{STORE_PATH}/usage-reservations".freeze

  def initialize(configuration:, subject:, authorization_token:, checkout_context: nil, checkout_target: nil)
    super(configuration: configuration, subject: subject, authorization_token: authorization_token)
    @checkout_context = checkout_target ? checkout_context.merge('target' => checkout_target) : checkout_context
  end

  def subscriptions!(page: 1, page_size: 20, service_id: nil)
    Autonomia::Financial::StoreContract.validate!('pagination', { 'page' => page, 'pageSize' => page_size, 'totalItems' => 0, 'totalPages' => 0 })
    Autonomia::Financial::StoreContract.validate!('uuid', service_id) if service_id
    filter = service_id ? "&serviceCatalogItemId=#{service_id}" : ''
    result = request_json(:get, "#{STORE_PATH}/service-subscriptions?page=#{page}&pageSize=#{page_size}#{filter}", 'serviceSubscriptionListResponse')
    validate_buyer!(result)
    result.fetch('data').each do |entry|
      validate_entry!(entry)
      raise Autonomia::Financial::StoreClientError, 'RESPONSE_TARGET_MISMATCH' if service_id && entry.dig('service', 'id') != service_id
    end
    result
  end

  def service_subscription!(id)
    Autonomia::Financial::StoreContract.validate!('uuid', id)
    result = request_json(:get, "#{STORE_PATH}/service-subscriptions/#{id}", 'serviceSubscriptionDetailResponse')
    validate_buyer!(result)
    validate_entry!(result.fetch('data'))
    raise Autonomia::Financial::StoreClientError, 'RESPONSE_TARGET_MISMATCH' unless result.dig('data', 'subscription', 'id') == id

    result
  end

  def checkout!(payload, idempotency_key:)
    Autonomia::Financial::StoreContract.validate!('checkoutRequest', payload)
    result = request_json(:post, "#{STORE_PATH}/checkout-sessions", 'checkoutResponse', payload: payload, idempotency_key: idempotency_key)
    validate_buyer!(result, outcome: 'unknown')
    unless result['checkoutIntentId'] == @checkout_context.fetch('checkoutIntentId') && result['servicePlanPriceId'] == payload['servicePlanPriceId']
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
    end

    validate_checkout_url!(result['checkoutUrl'])
    result
  end

  def checkout_state!(id, intent_id:, price_id:)
    Autonomia::Financial::StoreContract.validate!('uuid', id)
    result = request_json(:get, "#{STORE_PATH}/checkout-sessions/#{id}", 'checkoutStatusResponse')
    validate_checkout_state!(result, intent_id, price_id)
    raise Autonomia::Financial::StoreClientError, 'RESPONSE_TARGET_MISMATCH' unless result.dig('checkout', 'id') == id

    result
  end

  def resolve_checkout!(intent_id, price_id:)
    body = { 'idempotencyKey' => intent_id }
    Autonomia::Financial::StoreCheckoutContract.validate!('checkoutResolveRequest', body)
    result = request_json(:post, "#{STORE_PATH}/checkout-sessions/resolve", 'checkoutStatusResponse', payload: body)
    validate_checkout_state!(result, intent_id, price_id)
    result
  end

  def reserve!(body)
    Autonomia::Financial::StoreContract.validate!('reserveRequest', body)
    result = usage_request(:post, USAGE_PATH, body)
    unless %w[serviceSubscriptionId metricKey quantity resourceRef].all? { |key| result.fetch('reservation')[key] == body[key] }
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
    end

    result
  end

  def reservation!(id)
    Autonomia::Financial::StoreContract.validate!('uuid', id)
    result = usage_request(:get, "#{USAGE_PATH}/#{id}")
    validate_reservation_id!(result, id, outcome: 'failure')
    result
  end

  def commit!(id, body)
    settle_usage!(id, body, 'commit', 'commitRequest', 'committed')
  end

  def release!(id, body)
    settle_usage!(id, body, 'release', 'releaseRequest', 'released')
  end

  def entitlements!(body)
    Autonomia::Financial::StoreCheckoutContract.validate!('entitlementsResolveRequest', body)
    result = request_json(:post, "#{STORE_PATH}/entitlements/resolve", 'entitlementsResponse', payload: body)
    validate_namespace!(result.fetch('namespace'))
    raise Autonomia::Financial::StoreClientError, 'RESPONSE_TARGET_MISMATCH' unless body.all? { |key, value| result.fetch('data')[key] == value }

    result
  end

  private

  def raise_response_error(response, payload, method)
    code = payload.is_a?(Hash) && payload['error'].is_a?(Hash) ? payload.dig('error', 'code') : nil
    if %w[SERVICE_ALREADY_CONTRACTED USAGE_LIMIT_EXCEEDED IDEMPOTENCY_CONFLICT].include?(code)
      raise Autonomia::Financial::StoreClientError.new(code, status: response.code.to_i)
    end

    super
  end

  def settle_usage!(id, body, action, schema, status)
    Autonomia::Financial::StoreContract.validate!('uuid', id)
    Autonomia::Financial::StoreContract.validate!(schema, body)
    result = usage_request(:post, "#{USAGE_PATH}/#{id}/#{action}", body)
    validate_reservation_id!(result, id, outcome: 'unknown')
    raise Autonomia::Financial::StoreClientError.new('RESPONSE_STATE_MISMATCH', outcome: 'unknown') unless result.dig('reservation',
                                                                                                                      'status') == status

    result
  end

  def usage_request(method, path, body = nil)
    result = request_json(method, path, 'reservationResponse', payload: body)
    validate_namespace!(result.dig('reservation', 'namespace'), outcome: method == :get ? 'failure' : 'unknown')
    result
  end

  def validate_buyer!(result, outcome: 'failure')
    validate_namespace!(result.fetch('namespace'), outcome: outcome)
    return if result.dig('buyer', 'cognitoSub') == @buyer_subject

    raise Autonomia::Financial::StoreClientError.new('RESPONSE_BUYER_MISMATCH', outcome: outcome)
  end

  def validate_entry!(entry)
    subscription = entry.fetch('subscription')
    validate_buyer!(subscription)
    validate_target!(entry.fetch('target'))
    ids_match = subscription['serviceCatalogItemId'] == entry.dig('service', 'id') &&
                subscription['planId'] == entry.dig('plan', 'id') && subscription['planPriceId'] == entry.dig('price', 'id')
    raise Autonomia::Financial::StoreClientError, 'RESPONSE_TARGET_MISMATCH' unless ids_match
  end

  def validate_checkout_state!(result, intent_id, price_id)
    validate_buyer!(result)
    checkout = result.fetch('checkout')
    unless checkout['checkoutIntentId'] == intent_id && checkout['servicePlanPriceId'] == price_id
      raise Autonomia::Financial::StoreClientError, 'RESPONSE_TARGET_MISMATCH'
    end

    validate_checkout_url!(checkout['checkoutUrl']) if checkout['checkoutUrl']
  end

  def validate_checkout_url!(url)
    uri = URI.parse(url)
    return if uri.is_a?(URI::HTTPS) && uri.host == @base_uri.host && uri.port == @base_uri.port && uri.userinfo.nil? && uri.fragment.nil?

    raise Autonomia::Financial::StoreClientError.new('INVALID_CHECKOUT_URL', outcome: 'unknown')
  rescue URI::InvalidURIError
    raise Autonomia::Financial::StoreClientError.new('INVALID_CHECKOUT_URL', outcome: 'unknown')
  end

  def add_request_headers(request, method, path)
    request['X-Store-Actor-Assertion'] = @assertion.issue!(method, path, request.body,
                                                           idempotency_key: request['Idempotency-Key'], checkout_context: @checkout_context)
  end

  def parse_response(response, schema, method)
    return super if %w[catalogResponse managedServicesResponse serviceDraftResponse publicationResponse].include?(schema)

    result = JSON.parse(response.body.to_s)
    raise_response_error(response, result, method) unless response.is_a?(Net::HTTPSuccess)
    Autonomia::Financial::StoreCheckoutContract.validate!(schema, result)
  rescue JSON::ParserError, URI::InvalidURIError, Autonomia::Financial::StoreContractError
    raise Autonomia::Financial::StoreClientError.new('INVALID_RESPONSE', outcome: method == :get ? 'failure' : 'unknown')
  end
end
