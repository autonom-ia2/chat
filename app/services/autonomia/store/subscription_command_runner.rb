# frozen_string_literal: true

class Autonomia::Store::SubscriptionCommandRunner
  LEASE_SECONDS = 180

  def initialize(command)
    @command = command
    @token = SecureRandom.uuid
  end

  def run!
    return unless @command.state == 'pending'

    claim_lease!
    client = Autonomia::Store::BuyerClient.fetch!(@command, client_class: Autonomia::Financial::StoreLifecycleClient)
    result = if @command.command_action == 'schedule'
               client.schedule_cancellation!(@command.service_subscription_id, @command.financial_payload)
             else
               client.resume_renewal!(@command.service_subscription_id, @command.financial_payload)
             end
    checkpoint!(state: 'confirmed', receipt: result, error_code: nil)
  rescue Autonomia::Financial::StoreClientError => e
    record_error!(e)
  ensure
    lease_scope.update_all(processing_token: nil, processing_at: nil) # rubocop:disable Rails/SkipsModelValidations -- owned lease release
  end

  private

  def record_error!(error)
    state = error.outcome == 'unknown' || error.status >= 500 || error.status == 401 ? 'pending' : 'blocked'
    checkpoint!(state: state, error_code: error.code) unless error.code == 'OPERATION_BUSY'
    Rails.logger.warn("[autonomia][store] action=subscription_command_#{state} command_id=#{@command.id} code=#{error.code}")
  end

  def claim_lease!
    scope = Autonomia::Store::SubscriptionCommand.where(id: @command.id, state: 'pending')
                                                 .where('processing_at IS NULL OR processing_at < ?', Time.current - LEASE_SECONDS)
    claimed = scope.update_all(processing_at: Time.current, processing_token: @token) # rubocop:disable Rails/SkipsModelValidations -- compare-and-set lease
    raise Autonomia::Financial::StoreClientError.new('OPERATION_BUSY', status: 503) unless claimed == 1
  end

  def lease_scope
    Autonomia::Store::SubscriptionCommand.where(id: @command.id, processing_token: @token)
  end

  def checkpoint!(**attributes)
    lease_scope.where(state: 'pending').update_all(attributes.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations -- lease-owned checkpoint
  end
end
