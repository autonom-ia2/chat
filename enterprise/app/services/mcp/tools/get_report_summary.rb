class Mcp::Tools::GetReportSummary < Mcp::Tools::Base
  MAX_DAYS = 366
  BRASILIA_OFFSET = -3

  tool_name 'get_report_summary'
  description 'Summary of the account in a period: conversations, messages received and sent, resolutions, average first ' \
              'response and resolution times (seconds). Also returns the same numbers for the period just before, to compare.'
  scope 'reports:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(
    properties: {
      since: { type: 'string', format: 'date', description: 'First day, YYYY-MM-DD.' },
      until: { type: 'string', format: 'date', description: 'Last day, YYYY-MM-DD, included.' },
      timezone_offset: { type: 'number', description: 'Hours from UTC. Defaults to -3 (Brasília).' }
    },
    required: %w[since until]
  )

  def self.perform(since:, until:, timezone_offset: BRASILIA_OFFSET)
    zone = ActiveSupport::TimeZone[timezone_offset]
    return error_response('timezone_offset must be hours from UTC, like -3.') if zone.nil?

    first_day = Date.iso8601(since)
    days = (Date.iso8601(binding.local_variable_get(:until)) - first_day).to_i + 1
    return error_response("The period must have between 1 and #{MAX_DAYS} days.") unless days.between?(1, MAX_DAYS)

    respond(periods(zone.local(first_day.year, first_day.month, first_day.day), days, timezone_offset))
  rescue Date::Error, TypeError
    error_response('Use dates like 2026-11-21.')
  end

  # The period asked for and the one of the same length just before it, to compare.
  def self.periods(first, days, timezone_offset)
    { period: summary(first, first + days.days - 1.second, timezone_offset),
      previous_period: summary(first - days.days, first - 1.second, timezone_offset) }
  end
  private_class_method :periods

  def self.summary(first, last, timezone_offset)
    params = { type: :account, since: first.to_i.to_s, until: last.to_i.to_s, timezone_offset: timezone_offset, business_hours: false }
    V2::Reports::Conversations::MetricBuilder.new(Current.account, params).summary.merge(since: first.iso8601, until: last.iso8601)
  end
  private_class_method :summary
end
