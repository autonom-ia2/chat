module Autonomia::Agents::DraftRetention
  DEFAULT_HOURS = 48

  module_function

  def hours
    value = Integer(ENV.fetch('AUTONOMIA_DRAFT_REAP_HOURS', DEFAULT_HOURS))
    value.positive? ? value : DEFAULT_HOURS
  rescue ArgumentError, TypeError
    DEFAULT_HOURS
  end
end
