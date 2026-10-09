module Autonomia::Agents::RateLimits
  DEFAULTS = { build_threads: 60, test: 30, suggest: 30, copy_source: 10 }.freeze

  module_function

  def values
    DEFAULTS.to_h do |action, default|
      value = Integer(ENV.fetch("RATE_LIMIT_AUTONOMIA_#{action.to_s.upcase}", default.to_s), 10)
      raise ArgumentError, "#{action} rate limit must be a positive integer" unless value.positive?

      [action, value]
    end
  end
end
