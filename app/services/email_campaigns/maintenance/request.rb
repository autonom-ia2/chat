class EmailCampaigns::Maintenance::Request
  class Invalid < StandardError; end

  KEYS = %w[mode confirm reason idempotency_key batch_size].freeze
  attr_reader :attributes

  def initialize(parameters)
    values = parameters.to_h.stringify_keys
    raise Invalid, 'unsupported_parameter' if (values.keys - KEYS).any?

    mode = values.fetch('mode', 'dry_run')
    raise Invalid, 'invalid_mode' unless %w[dry_run apply].include?(mode)

    raise Invalid, 'invalid_confirm' if mode == 'apply' ? values['confirm'] != 'apply' : values.key?('confirm')

    @attributes = { dry_run: mode != 'apply', reason: reason(values), idempotency_key: key(values), batch_size: batch_size(values) }
  end

  private

  def reason(values)
    value = values.fetch('reason', '')
    raise Invalid, 'invalid_reason' unless value.is_a?(String) && value.strip.length.between?(1, 200)

    value.strip
  end

  def key(values)
    value = values['idempotency_key']
    raise Invalid, 'invalid_idempotency_key' unless value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)

    value
  end

  def batch_size(values)
    value = values.fetch('batch_size', 100)
    raise Invalid, 'invalid_batch_size' unless value.to_s.match?(/\A[0-9]{1,3}\z/) && (1..500).cover?(value.to_i)

    value.to_i
  end
end
