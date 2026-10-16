# frozen_string_literal: true

class Autonomia::Financial::StoreLifecycleClient < Autonomia::Financial::StoreCheckoutClient
  def cancellation!(id)
    cancellation_request(:get, id, nil)
  end

  def schedule_cancellation!(id, body)
    cancellation_request(:post, id, body)
  end

  def resume_renewal!(id, body)
    cancellation_request(:post, id, body, resume: true)
  end

  def reconcile_checkout!(id, body)
    Autonomia::Financial::StoreContract.validate!('uuid', id)
    Autonomia::Financial::StoreLifecycleContract.validate!('reconciliationRequest', body)
    path = "#{STORE_PATH}/checkout-sessions/#{id}"
    result = request_json(:post, "#{path}/reconcile", 'reconciliationResponse', payload: body)
    validate_buyer!(result, outcome: 'unknown')
    unless result.dig('operation', 'statusUrl') == path
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
    end

    result
  end

  private

  def cancellation_request(method, id, body, resume: false)
    Autonomia::Financial::StoreContract.validate!('uuid', id)
    Autonomia::Financial::StoreLifecycleContract.validate!('cancellationCommandRequest', body) if body
    path = "#{STORE_PATH}/service-subscriptions/#{id}/cancellation#{resume ? '/resume' : ''}"
    schema = method == :get ? 'cancellationCapability' : 'cancellationCommandResponse'
    result = request_json(method, path, schema, payload: body)
    outcome = method == :get ? 'failure' : 'unknown'
    validate_buyer!(result, outcome: outcome)
    raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: outcome) unless result.dig('data',
                                                                                                                     'serviceSubscriptionId') == id

    validate_command!(result, body, resume: resume) if body
    result
  end

  def validate_command!(result, body, resume:)
    expected_type = resume ? 'subscription_renewal_resumed' : 'subscription_non_renewal_scheduled'
    valid = result.dig('command', 'idempotencyKey') == body.fetch('idempotencyKey') &&
            result.dig('result', 'type') == expected_type && result.dig('result', 'previousVersion') == body.fetch('expectedVersion') &&
            result.dig('result', 'appliedVersion') == result.dig('data', 'subscriptionVersion')
    raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown') unless valid
  end

  def parse_response(response, schema, method)
    return super unless %w[cancellationCapability cancellationCommandResponse reconciliationResponse].include?(schema)

    result = JSON.parse(response.body.to_s)
    raise_response_error(response, result, method) unless response.is_a?(Net::HTTPSuccess)
    Autonomia::Financial::StoreLifecycleContract.validate!(schema, result)
  rescue JSON::ParserError, Autonomia::Financial::StoreContractError
    raise Autonomia::Financial::StoreClientError.new('INVALID_RESPONSE', outcome: method == :get ? 'failure' : 'unknown')
  end
end
