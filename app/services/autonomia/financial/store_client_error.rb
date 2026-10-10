# frozen_string_literal: true

class Autonomia::Financial::StoreClientError < Autonomia::Financial::Client::Error
  attr_reader :code, :outcome

  def initialize(code, status: 502, outcome: 'failure')
    super('Financial store request failed.', status: status, payload: { 'code' => code, 'outcome' => outcome })
    @code = code
    @outcome = outcome
  end
end
