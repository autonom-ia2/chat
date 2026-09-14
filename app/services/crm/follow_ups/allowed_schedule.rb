# Shared by planning, execution and retries. Missing days preserve the legacy seven-day schedule.
class Crm::FollowUps::AllowedSchedule
  def initialize(config:, timezone:)
    config = config.with_indifferent_access
    @days = config.fetch(:allowed_days, (0..6).to_a)
    raise ArgumentError, 'invalid allowed days' unless @days.is_a?(Array) && @days.any? && @days.all? { |day| (0..6).cover?(day) }

    quiet = config[:quiet_hours].to_h.with_indifferent_access
    @start_hour = quiet[:start].to_i
    @end_hour = quiet[:end].to_i
    @timezone = timezone
  end

  def next_at(candidate)
    local = candidate.in_time_zone(@timezone)
    8.times do
      permitted = permitted_time(local) if @days.include?(local.wday)
      return permitted.utc if permitted

      local = local.next_day.beginning_of_day
    end
    raise ArgumentError, 'no allowed schedule'
  end

  private

  def permitted_time(local)
    return local if @start_hour >= @end_hour

    start = local.change(hour: @start_hour, min: 0, sec: 0)
    return start if local < start
    return local if local < local.change(hour: @end_hour, min: 0, sec: 0)

    nil
  end
end
