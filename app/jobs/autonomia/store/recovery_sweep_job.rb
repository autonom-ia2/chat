# frozen_string_literal: true

class Autonomia::Store::RecoverySweepJob < ApplicationJob
  queue_as :scheduled_jobs
  BATCH_SIZE = 20
  PENDING_INTERVAL = 5.minutes
  READY_INTERVAL = 15.minutes

  def perform
    installation = ENV.fetch('FINANCIAL_STORE_INSTALLATION_ID', '')
    product = ENV.fetch('FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID', '')
    return if installation.blank? || product.blank?

    scope = { installation_id: installation, product_catalog_item_id: product }
    lease_cutoff = Time.current - Autonomia::Store::ActivationRunner::LEASE_SECONDS
    activations = Autonomia::Store::Activation.where(scope).where.not(state: %w[disabled failed])
                                              .where('processing_at IS NULL OR processing_at < ?', lease_cutoff)
    enqueue_due(activations, Autonomia::Store::ActivationJob)
    intents = Autonomia::Store::CheckoutIntent.where(scope).where.not(state: 'completed')
                                              .where("state NOT IN ('expired', 'failed') OR reconciliation_requested")
    enqueue_due(intents, Autonomia::Store::CheckoutRecoveryJob)
    recover_commands(scope)
    events = Autonomia::Store::Event.where(state: 'pending').where("payload -> 'namespace' ->> 'installationId' = ?", installation)
                                    .where("payload -> 'namespace' ->> 'productCatalogItemId' = ?", product)
    enqueue_due(events, Autonomia::Store::EventJob)
  end

  private

  def recover_commands(scope)
    cutoff = Time.current - Autonomia::Store::SubscriptionCommandRunner::LEASE_SECONDS
    commands = Autonomia::Store::SubscriptionCommand.where(scope).where(state: 'pending')
                                                    .where('processing_at IS NULL OR processing_at < ?', cutoff)
    enqueue_due(commands, Autonomia::Store::SubscriptionCommandJob)
  end

  def enqueue_due(scope, job)
    scope.where('next_recovery_at <= ?', Time.current).order(:next_recovery_at, :id).limit(BATCH_SIZE).each do |record|
      interval = record.state == 'ready' ? READY_INTERVAL : PENDING_INTERVAL
      # Claim scheduling before enqueue. A lost enqueue becomes due again, without
      # advancing the business checkpoint or creating another remote operation.
      claimed = scope.where(id: record.id, state: record.state, next_recovery_at: record.next_recovery_at)
                     .update_all(next_recovery_at: Time.current + interval) # rubocop:disable Rails/SkipsModelValidations -- atomic scheduling claim
      job.perform_later(record.id) if claimed == 1
    end
  end
end
