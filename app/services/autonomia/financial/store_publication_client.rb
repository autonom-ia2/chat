# frozen_string_literal: true

class Autonomia::Financial::StorePublicationClient < Autonomia::Financial::StoreClient
  def initialize(configuration:, subject:, authorization_token:)
    super(authorization_token: authorization_token, installation_api_key: configuration.api_key,
          namespace: configuration.namespace, buyer_subject: subject, base_url: configuration.base_url)
    @assertion = Autonomia::Financial::StoreActorAssertion.new(configuration: configuration, subject: subject)
  end

  def agent_services!(principal_id)
    raise ArgumentError, 'Invalid principal.' unless principal_id.is_a?(Integer) && principal_id.positive?

    payload = request_json(:get, "#{STORE_PATH}/services?principalAgentId=#{principal_id}", 'managedServicesResponse')
    validate_namespace!(payload.fetch('namespace'))
    payload
  end

  def create_service!(payload)
    Autonomia::Financial::StorePublicationContract.validate!('serviceDraftRequest', payload)
    validate_target!(payload.fetch('target'))
    response = request_json(:post, "#{STORE_PATH}/services", 'serviceDraftResponse', payload: payload)
    validate_namespace!(response.fetch('namespace'), outcome: 'unknown')
    raise Autonomia::Financial::StoreClientError.new('RESPONSE_STATE_MISMATCH', outcome: 'unknown') unless response.dig('service',
                                                                                                                        'status') == 'inactive'

    response
  end

  def feature_services!(key)
    Autonomia::Financial::StoreFeatures.target!(key)
    payload = request_json(:get, "#{STORE_PATH}/services?featureKey=#{key}", 'managedServicesResponse')
    validate_namespace!(payload.fetch('namespace'))
    payload
  end

  def publication!(service_id, target:)
    publication_request(:get, service_id, target: target)
  end

  def publish!(service_id, payload)
    Autonomia::Financial::StorePublicationContract.validate!('publicationRequest', payload)
    response = publication_request(:put, service_id, target: payload.fetch('target'), payload: payload)
    unless payload.all? { |key, value| response.fetch('publication')[key] == value }
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
    end

    response
  end

  private

  def raise_response_error(response, payload, method)
    allowed = %w[UNAUTHORIZED FORBIDDEN NOT_FOUND CONFLICT INVALID_REQUEST STORE_AUTH_UNAVAILABLE]
    code = payload.is_a?(Hash) && payload['error'].is_a?(Hash) ? payload.dig('error', 'code') : nil
    code = 'UPSTREAM_REJECTED' unless allowed.include?(code)
    status = response.code.to_i
    raise Autonomia::Financial::StoreClientError.new(code, status: status, outcome: method != :get && status >= 500 ? 'unknown' : 'failure')
  end

  def publication_request(method, service_id, target:, payload: nil)
    Autonomia::Financial::StoreContract.validate!('uuid', service_id)
    validate_target!(target)
    response = request_json(method, "#{STORE_PATH}/publications/#{service_id}", 'publicationResponse', payload: payload)
    validate_namespace!(response.fetch('namespace'), outcome: method == :get ? 'failure' : 'unknown')
    matches_target = response.fetch('publication')['target'] == target
    matches_id = response.dig('publication', 'serviceCatalogItemId') == service_id && response.dig('service', 'id') == service_id
    unless matches_target && matches_id
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: method == :get ? 'failure' : 'unknown')
    end

    response
  end

  def validate_target!(target)
    Autonomia::Financial::StoreContract.validate!('target', target)
    if target.fetch('type') == 'feature'
      Autonomia::Financial::StoreFeatures.target!(target.fetch('featureKey'))
      return
    end
    return if target.fetch('installationId') == @namespace.fetch('installationId')

    raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403)
  end

  def add_request_headers(request, method, path)
    request['X-Store-Actor-Assertion'] = @assertion.issue!(method, path, request.body)
  end

  def parse_response(response, schema, method)
    return super if schema == 'catalogResponse'

    payload = JSON.parse(response.body.to_s)
    raise_response_error(response, payload, method) unless response.is_a?(Net::HTTPSuccess)
    Autonomia::Financial::StorePublicationContract.validate!(schema, payload)
  rescue JSON::ParserError, Autonomia::Financial::StoreContractError
    raise Autonomia::Financial::StoreClientError.new('INVALID_RESPONSE', outcome: method == :get ? 'failure' : 'unknown')
  end
end
