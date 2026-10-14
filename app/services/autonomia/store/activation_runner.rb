# frozen_string_literal: true

class Autonomia::Store::ActivationRunner
  LEASE_SECONDS = 180
  RESOURCE_ERRORS = %w[AGENT_PRINCIPAL_UNAVAILABLE AGENT_INSTANCE_DELETED].freeze

  def initialize(activation)
    @activation = activation
    @token = SecureRandom.uuid
  end

  def run!
    claim_lease!
    6.times do
      @activation.reload
      return if %w[disabled failed].include?(@activation.state)

      raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403) unless @activation.processing_token == @token

      if @activation.state == 'ready'
        sync_agent_access! # Expired grants must stop mirrors even while Financial is unavailable.
        refresh_snapshot!
        checkpoint!({ error_code: nil }, from: ['ready'])
        sync_agent_access!
        return
      end
      advance!
    end
  rescue Autonomia::Financial::StoreClientError => e
    checkpoint!({ error_code: e.code })
    raise
  ensure
    lease_scope.update_all(processing_token: nil, processing_at: nil) # rubocop:disable Rails/SkipsModelValidations -- atomic lease release
  end

  private

  def claim_lease!
    scope = Autonomia::Store::Activation.where(id: @activation.id).where('processing_at IS NULL OR processing_at < ?', Time.current - LEASE_SECONDS)
    claimed = scope.update_all(processing_at: Time.current, processing_token: @token) # rubocop:disable Rails/SkipsModelValidations -- atomic compare-and-set
    raise Autonomia::Financial::StoreClientError.new('OPERATION_BUSY', status: 503) unless claimed == 1
  end

  def lease_scope
    Autonomia::Store::Activation.where(id: @activation.id, processing_token: @token)
  end

  def advance!
    case @activation.state
    when 'preparing' then reserve!
    when 'reserved' then commit!
    when 'committed' then confirm_access!
    when 'disabling' then release!
    end
  end

  def beneficiary_eligible?
    membership = @activation.user&.account_users&.find_by(account_id: @activation.account_id)
    membership&.administrator? && @activation.account&.active?
  end

  def client
    @client ||= Autonomia::Store::BuyerClient.fetch!(@activation)
  end

  def reserve!
    raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403) unless beneficiary_eligible?

    Autonomia::Store::AgentInstance.principal!(@activation.target) if @activation.target['type'] == 'agent'

    checkpoint!({ reserve_attempted: true })
    result = client.reserve!(reserve_body)
    reservation = result.fetch('reservation')
    checkpoint!({ reservation_id: reservation.fetch('id') })
    checkpoint_reservation!(reservation.fetch('status'), from: ['preparing'])
  end

  def commit!
    result = client.reservation!(@activation.reservation_id)
    verify_reservation!(result)
    status = result.dig('reservation', 'status')
    unless status == 'reserved'
      checkpoint_reservation!(status, from: ['reserved'])
      return
    end

    result = client.commit!(@activation.reservation_id, 'idempotencyKey' => @activation.intent_key('commit'))
    verify_reservation!(result)
    checkpoint!({ state: 'committed', error_code: nil }, from: ['reserved'])
  rescue Autonomia::Financial::StoreClientError => e
    raise unless e.status == 409

    # Expiration/release may race the preceding read. Query the same reservation;
    # never create another one to resolve an indeterminate commit.
    result = client.reservation!(@activation.reservation_id)
    verify_reservation!(result)
    raise if result.dig('reservation', 'status') == 'reserved'

    checkpoint_reservation!(result.dig('reservation', 'status'), from: ['reserved'])
  end

  def checkpoint_reservation!(status, from:)
    state = { 'reserved' => 'reserved', 'committed' => 'committed', 'released' => 'disabled', 'expired' => 'failed' }.fetch(status)
    checkpoint!({ state: state, error_code: status == 'expired' ? 'RESERVATION_EXPIRED' : nil }, from: from)
  end

  def confirm_access!
    unless beneficiary_eligible?
      checkpoint!({ state: 'disabling' })
      return
    end
    snapshot = refresh_snapshot!
    unless snapshot && Autonomia::Store::GrantPolicy.allowed?(snapshot, subscription_id: @activation.service_subscription_id,
                                                                        reservation_id: @activation.reservation_id)
      raise Autonomia::Financial::StoreClientError.new('ENTITLEMENT_PENDING', status: 503)
    end

    prepare_resource!
    @activation.reload
    sync_agent_access!
  end

  def prepare_resource!
    @activation.with_lock do
      return unless @activation.state == 'committed' && @activation.processing_token == @token

      Autonomia::Store::AgentInstance.provision!(@activation) if @activation.target['type'] == 'agent'
      checkpoint!({ state: 'ready', error_code: nil }, from: ['committed'])
    end
  rescue Autonomia::Financial::StoreClientError => e
    raise unless RESOURCE_ERRORS.include?(e.code)

    checkpoint!({ state: 'disabling', error_code: e.code }, from: ['committed'])
  end

  def release!
    if @activation.reservation_id.nil? && @activation.reserve_attempted
      # Recovery uses the same persisted intent, quantity and timestamp, never a new reservation key.
      result = client.reserve!(reserve_body)
      checkpoint!({ reservation_id: result.dig('reservation', 'id') })
      @activation.reload
    end
    release_reservation! if @activation.reservation_id
    checkpoint!({ state: 'disabled', error_code: resource_error }, from: ['disabling'])
    sync_agent_access!
    refresh_snapshot! if @activation.account_id && @activation.reservation_id
  end

  def release_reservation!
    result = client.reservation!(@activation.reservation_id)
    verify_reservation!(result)
    return if %w[released expired].include?(result.dig('reservation', 'status'))

    result = client.release!(@activation.reservation_id, 'idempotencyKey' => @activation.intent_key('release'), 'reason' => 'resource_disabled')
    verify_reservation!(result)
  rescue Autonomia::Financial::StoreClientError => e
    raise unless e.status == 409

    result = client.reservation!(@activation.reservation_id)
    verify_reservation!(result)
    raise unless %w[released expired].include?(result.dig('reservation', 'status'))
  end

  def sync_agent_access!
    Autonomia::Store::AgentInstance.sync_access!(@activation.agent) if @activation.agent
  end

  def resource_error
    @activation.error_code if RESOURCE_ERRORS.include?(@activation.error_code)
  end

  def reserve_body
    { 'serviceSubscriptionId' => @activation.service_subscription_id, 'metricKey' => @activation.metric_key,
      'quantity' => 1, 'resourceRef' => @activation.resource_ref,
      'idempotencyKey' => @activation.intent_key('reserve'), 'occurredAt' => @activation.occurred_at.iso8601 }
  end

  def refresh_snapshot!
    snapshot = client.entitlements!('serviceCatalogItemId' => @activation.service_catalog_item_id, 'resourceRef' => @activation.resource_ref)
    Autonomia::Store::Projection.apply!(snapshot)&.reload&.payload
  end

  def verify_reservation!(result)
    reservation = result.fetch('reservation')
    unless reservation['resourceRef'] == @activation.resource_ref && reservation['serviceSubscriptionId'] == @activation.service_subscription_id &&
           reservation['metricKey'] == @activation.metric_key && reservation['quantity'] == 1
      raise Autonomia::Financial::StoreClientError.new('RESPONSE_TARGET_MISMATCH', outcome: 'unknown')
    end
  end

  def checkpoint!(attributes, from: nil)
    relation = lease_scope
    relation = relation.where(state: from) if from
    relation.update_all(attributes.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations -- checkpoint owned by atomic lease
  end
end
