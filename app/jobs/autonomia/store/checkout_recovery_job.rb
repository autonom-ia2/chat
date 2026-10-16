# frozen_string_literal: true

class Autonomia::Store::CheckoutRecoveryJob < ApplicationJob
  queue_as :low

  def perform(id)
    intent = Autonomia::Store::CheckoutIntent.find_by(id: id)
    return unless intent

    Autonomia::Store::CheckoutRecovery.new(intent).run!
  rescue Autonomia::Financial::StoreClientError => e
    intent.with_lock { intent.update!(error_code: e.code) unless %w[completed expired failed].include?(intent.state) }
    Rails.logger.warn("[autonomia][store] action=checkout_recovery_pending intent_id=#{id} code=#{e.code}")
  end
end
