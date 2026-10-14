# frozen_string_literal: true

class Api::V1::Accounts::Autonomia::StoreSubscriptionController < Api::V1::Accounts::Autonomia::StoreCustomerController
  def cancellation
    result = lifecycle_client.cancellation!(subscription_id)
    pending = command_scope.find_by(service_subscription_id: subscription_id, state: 'pending')
    render json: result.merge('localCommand' => pending&.public_payload)
  end

  def schedule_cancellation
    submit_command('schedule')
  end

  def resume_renewal
    submit_command('resume')
  end

  def command
    render json: { data: owned_command.public_payload }
  end

  def retry_command
    record = owned_command
    raise ::Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409) unless record.state == 'pending'

    ::Autonomia::Store::SubscriptionCommandJob.perform_later(record.id)
    render json: { data: record.public_payload }, status: :accepted
  end

  private

  def subscription_id
    ::Autonomia::Financial::StoreContract.validate!('uuid', params[:id])
    params[:id]
  end

  def command_scope
    ::Autonomia::Store::SubscriptionCommand.where(user: Current.user, buyer_subject: verified_subject,
                                                  installation_id: store_configuration.namespace.fetch('installationId'),
                                                  product_catalog_item_id: store_configuration.namespace.fetch('productCatalogItemId'))
  end

  def owned_command
    ::Autonomia::Financial::StoreContract.validate!('uuid', params[:id])
    command_scope.find(params[:id])
  end

  def lifecycle_client
    @lifecycle_client ||= ::Autonomia::Financial::StoreLifecycleClient.new(configuration: store_configuration,
                                                                           subject: verified_subject, authorization_token: @authorization_token)
  end

  def submit_command(action)
    body = customer_body('clientIntent', 'expectedVersion')
    ::Autonomia::Financial::StoreContract.validate!('uuid', body['clientIntent'])
    ::Autonomia::Financial::StoreLifecycleContract.validate!(
      'cancellationCommandRequest', { 'contractVersion' => 1, 'idempotencyKey' => body['clientIntent'], 'expectedVersion' => body['expectedVersion'] }
    )
    record = ::Autonomia::Store::SubscriptionCommand.find_by(user: Current.user, client_intent: body.fetch('clientIntent'))
    record ||= create_command!(body, action)
    verify_command!(record, body, action)
    ::Autonomia::Store::SubscriptionCommandJob.perform_later(record.id) if record.state == 'pending'
    render json: { data: record.public_payload }, status: :accepted
  end

  def verify_command!(record, body, action)
    expected = { buyer_subject: verified_subject, installation_id: store_configuration.namespace.fetch('installationId'),
                 product_catalog_item_id: store_configuration.namespace.fetch('productCatalogItemId'), service_subscription_id: subscription_id,
                 command_action: action, expected_version: body.fetch('expectedVersion') }
    raise ::Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409) unless expected.all? { |key, value| record.public_send(key) == value }
  end

  def create_command!(body, action)
    capability = lifecycle_client.cancellation!(subscription_id).fetch('data')
    allowed = capability.fetch(action == 'schedule' ? 'canSchedule' : 'canResume') &&
              capability.fetch('subscriptionVersion') == body.fetch('expectedVersion')
    raise ::Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409) unless allowed

    command_scope.create_or_find_by!(client_intent: body.fetch('clientIntent')) do |record|
      record.service_subscription_id = subscription_id
      record.command_action = action
      record.expected_version = body.fetch('expectedVersion')
    end
  rescue ActiveRecord::RecordNotFound
    # A different pending intent already occupies this owner contract's unique slot.
    raise ::Autonomia::Financial::StoreClientError.new('CONFLICT', status: 409)
  end
end
