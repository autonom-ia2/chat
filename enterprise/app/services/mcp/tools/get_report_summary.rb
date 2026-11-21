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

    first = zone.parse(since).beginning_of_day
    last = zone.parse(binding.local_variable_get(:until)).end_of_day
    return error_response("The period must have between 1 and #{MAX_DAYS} days.") unless first <= last && (last - first) <= MAX_DAYS.days

    previous_first = first - (last - first) - 1.second
    respond(period: summary(first, last, timezone_offset), previous_period: summary(previous_first, first - 1.second, timezone_offset))
  rescue ArgumentError, TypeError
    error_response('Use dates like 2026-11-21.')
  end

  def self.summary(first, last, timezone_offset)
    params = { type: :account, since: first.to_i.to_s, until: last.to_i.to_s, timezone_offset: timezone_offset, business_hours: false }
    V2::Reports::Conversations::MetricBuilder.new(Current.account, params).summary.merge(since: first.iso8601, until: last.iso8601)
  end
  private_class_method :summary
end
