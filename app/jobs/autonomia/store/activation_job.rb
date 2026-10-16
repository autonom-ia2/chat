# frozen_string_literal: true

class Autonomia::Store::ActivationJob < ApplicationJob
  queue_as :low
  retry_on Autonomia::Financial::StoreClientError, wait: 30.seconds, attempts: 8 do |job, error|
    Rails.logger.warn("[autonomia][store] action=activation_pending activation_id=#{job.arguments.first} code=#{error.code}")
  end

  def perform(id)
    activation = Autonomia::Store::Activation.find_by(id: id)
    return unless activation

    Autonomia::Store::ActivationRunner.new(activation).run!
  rescue Autonomia::Financial::StoreClientError => e
    raise if e.status >= 500 || e.outcome == 'unknown'

    Rails.logger.warn("[autonomia][store] action=activation_rejected activation_id=#{id} code=#{e.code}")
  end
end
