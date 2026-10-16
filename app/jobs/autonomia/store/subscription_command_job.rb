# frozen_string_literal: true

class Autonomia::Store::SubscriptionCommandJob < ApplicationJob
  queue_as :low

  def perform(id)
    command = Autonomia::Store::SubscriptionCommand.find_by(id: id)
    Autonomia::Store::SubscriptionCommandRunner.new(command).run! if command
  end
end
