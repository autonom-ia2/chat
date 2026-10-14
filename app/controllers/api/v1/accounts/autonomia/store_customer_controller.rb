# frozen_string_literal: true

class Api::V1::Accounts::Autonomia::StoreCustomerController < Api::V1::Accounts::Autonomia::StoreController
  wrap_parameters false
  skip_before_action :fetch_target
  before_action :ensure_account_administrator

  def services
    result = store_client.subscriptions!(page: pagination_integer(:page, 1), page_size: pagination_integer(:page_size, 20),
                                         service_id: params[:serviceCatalogItemId])
    ids = result.fetch('data').map { |entry| entry.dig('subscription', 'id') }
    records = activation_scope.where(service_subscription_id: ids).order(:created_at).to_a
    render json: result.merge('activations' => activation_payloads(records))
  end

  def accounts
    rows = Current.user.account_users.joins(:account).where(role: :administrator, accounts: { status: :active })
    render json: { data: rows.order('accounts.id').pluck('accounts.id', 'accounts.name').map { |id, name| { id: id, name: name } } }
  end

  def activate
    body = activation_body
    membership = Current.user.account_users.joins(:account).where(role: :administrator,
                                                                  accounts: { status: :active }).find_by!(account_id: body['accountId'])
    subscription, metric, target = activation_subscription!(body.fetch('serviceSubscriptionId'))
    activation = build_activation!(body, membership, subscription, metric, target)
    restart_activation!(activation, body.fetch('clientIntent'), metric)
    ::Autonomia::Store::ActivationJob.perform_later(activation.id) unless %w[ready disabled].include?(activation.state)
    render json: { data: activation_payload(activation) }, status: :accepted
  end

  def activation
    render json: { data: activation_payload(owned_activation) }
  end

  def deactivate
    record = owned_activation
    record.with_lock { record.update!(state: 'disabling', error_code: nil) unless record.state == 'disabled' }
    ::Autonomia::Store::AgentInstance.sync_access!(record.agent) if record.agent
    ::Autonomia::Store::ActivationJob.perform_later(record.id) unless record.state == 'disabled'
    render json: { data: activation_payload(record) }, status: :accepted
  end

  def resume_activation
    record = owned_activation
    raise ::Autonomia::Financial::StoreClientError.new('ACTIVATION_NOT_ELIGIBLE', status: 409) if record.state == 'failed'

    ::Autonomia::Store::ActivationJob.perform_later(record.id)
    render json: { data: activation_payload(record) }, status: :accepted
  end

  private

  def ensure_account_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def customer_body(*allowed)
    body = request.request_parameters.except(controller_name, 'controller', 'action')
    raise ::Autonomia::Financial::StoreContractError, ['/'] unless (body.keys - allowed).empty?

    body
  end

  def verified_subject
    @verified_subject ||= ::Autonomia::Financial::StoreIdentity.subject!(@authorization_token)
  end

  def store_client
    @store_client ||= ::Autonomia::Financial::StoreCheckoutClient.new(configuration: store_configuration,
                                                                      subject: verified_subject, authorization_token: @authorization_token)
  end

  def activation_scope
    ::Autonomia::Store::Activation.where(user: Current.user, installation_id: store_configuration.namespace.fetch('installationId'),
                                         product_catalog_item_id: store_configuration.namespace.fetch('productCatalogItemId'))
  end

  def owned_activation
    ::Autonomia::Financial::StoreContract.validate!('uuid', params[:id])
    activation_scope.find(params[:id])
  end

  def activation_payload(record)
    projection = if record.state == 'ready'
                   ::Autonomia::Store::Entitlement.find_by(
                     account_id: record.account_id, service_catalog_item_id: record.service_catalog_item_id,
                     installation_id: record.installation_id, product_catalog_item_id: record.product_catalog_item_id
                   )
                 end
    record.public_payload(snapshot: projection&.payload)
  end

  def activation_payloads(records)
    projections = ::Autonomia::Store::Entitlement.where(
      installation_id: store_configuration.namespace.fetch('installationId'),
      product_catalog_item_id: store_configuration.namespace.fetch('productCatalogItemId'),
      account_id: records.map(&:account_id), service_catalog_item_id: records.map(&:service_catalog_item_id)
    ).index_by { |row| [row.account_id, row.service_catalog_item_id] }
    records.map { |row| row.public_payload(snapshot: projections[[row.account_id, row.service_catalog_item_id]]&.payload) }
  end

  def activation_body
    body = customer_body('serviceSubscriptionId', 'accountId', 'clientIntent')
    ::Autonomia::Financial::StoreContract.validate!('uuid', body['serviceSubscriptionId'])
    ::Autonomia::Financial::StoreContract.validate!('uuid', body['clientIntent'])
    unless body['accountId'].is_a?(Integer) && body['accountId'].between?(1, 9_999_999_999_999_999)
      raise ::Autonomia::Financial::StoreContractError, ['/accountId']
    end

    body
  end

  def activation_subscription!(id)
    entry = store_client.service_subscription!(id).fetch('data')
    subscription = entry.fetch('subscription')
    limits = subscription.fetch('limits').select { |limit| limit['usageBehavior'] == 'allocation' && limit['resetPeriod'] == 'none' }
    target = entry.fetch('target')
    validate_activation_target!(target)
    unless subscription.dig('access', 'allowed') && limits.one?
      raise ::Autonomia::Financial::StoreClientError.new('ACTIVATION_NOT_ELIGIBLE', status: 409)
    end

    [subscription, limits.first.fetch('metricKey'), target]
  end

  def validate_activation_target!(target)
    return ::Autonomia::Store::AgentInstance.principal!(target) if target['type'] == 'agent'
    return if target == { 'type' => 'feature', 'featureKey' => ::Autonomia::Financial::StoreFeatures::PILOT_KEY }

    raise ::Autonomia::Financial::StoreClientError.new('ACTIVATION_NOT_ELIGIBLE', status: 409)
  end

  def build_activation!(body, membership, subscription, metric, target)
    activation_scope.create_or_find_by!(account_id: membership.account_id, service_subscription_id: subscription.fetch('id')) do |record|
      record.buyer_subject = verified_subject
      record.resource_id = membership.account_id.to_s
      record.service_catalog_item_id = subscription.fetch('serviceCatalogItemId')
      record.target = target
      record.feature_key = target['featureKey']
      record.metric_key = metric
      record.operation_intent = body.fetch('clientIntent')
      record.occurred_at = Time.current
    end
  end

  def restart_activation!(activation, intent, metric)
    activation.with_lock do
      restartable = activation.state == 'disabled' || (activation.state == 'failed' && activation.error_code == 'RESERVATION_EXPIRED')
      if restartable && activation.operation_intent != intent
        activation.update!(state: 'preparing', operation_intent: intent, occurred_at: Time.current,
                           metric_key: metric, reservation_id: nil, reserve_attempted: false, error_code: nil, next_recovery_at: Time.current)
      end
    end
  end
end
