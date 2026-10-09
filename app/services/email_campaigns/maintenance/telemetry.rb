class EmailCampaigns::Maintenance::Telemetry
  CODES = %w[batch_finished batch_failed enqueue_failed run_failed].freeze

  def self.emit(code, run)
    raise ArgumentError, 'invalid_event_code' unless CODES.include?(code)

    Rails.logger.info({ event: "email_protection.#{code}", run: run.public_progress }.to_json)
  end
end
