# frozen_string_literal: true

class Autonomia::Financial::StoreContractError < StandardError
  attr_reader :paths

  def initialize(paths)
    super('Invalid Financial store contract payload.')
    @paths = paths
  end
end
