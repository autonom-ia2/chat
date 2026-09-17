class EmailCampaigns::Maintenance::Telemetry
  CODES = %w[batch_finished batch_failed enqueue_failed run_failed].freeze

  def self.emit(code, run)
    raise ArgumentError, 'invalid_event_code' unless CODES.include?(code)

    payload = { event: "email_protection.#{code}", run: run.public_progress }
    Rails.logger.info(payload.to_json)
    ActiveSupport::Notifications.instrument(payload[:event], payload)
  end
end
