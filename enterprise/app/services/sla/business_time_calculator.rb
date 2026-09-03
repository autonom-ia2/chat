class Sla::BusinessTimeCalculator
  MAX_DAYS = 800

  def initialize(schedule:)
    @schedule = schedule
    @timezone = ActiveSupport::TimeZone[schedule.timezone] || ActiveSupport::TimeZone['UTC']
  end

  # Seconds of business time between +from+ and +to+, counting only seconds inside
  # the schedule blocks, walking day by day in the schedule timezone. DST-safe:
  # each day is re-anchored with beginning_of_day in the zone. Short-circuits once
  # the accumulated total reaches +limit+ (the SLA threshold).
  def elapsed_seconds(from, to, limit: nil)
    return 0 if from.blank? || to.blank? || from >= to

    from = from.in_time_zone(@timezone)
    to = to.in_time_zone(@timezone)
    total = 0
    day_start = from.beginning_of_day

    MAX_DAYS.times do
      break if day_start > to

      block_ranges(day_start).each do |block_start, block_end|
        overlap = [to, block_end].min - [from, block_start].max
        total += overlap if overlap.positive?
      end
      return total.round if limit.present? && total >= limit

      day_start = (day_start + 1.day).beginning_of_day
    end

    total.round
  end

  # Inverse of +elapsed_seconds+: the first instant at which +threshold_seconds+ of
  # business time have elapsed since +start_time+. Walks the same blocks forward with
  # the same per-day anchoring, so elapsed_seconds(start, deadline(start, t)) == t.
  # Returns nil when the threshold is not reachable within MAX_DAYS.
  def deadline(start_time, threshold_seconds)
    return nil if start_time.blank? || threshold_seconds.nil?

    start_time = start_time.in_time_zone(@timezone)
    remaining = threshold_seconds.to_i
    return start_time unless remaining.positive?

    day_start = start_time.beginning_of_day

    MAX_DAYS.times do
      block_ranges(day_start).each do |block_start, block_end|
        counted_from = [start_time, block_start].max
        available = block_end - counted_from
        next unless available.positive?
        return counted_from + remaining.seconds if remaining <= available

        remaining -= available
      end

      day_start = (day_start + 1.day).beginning_of_day
    end

    nil
  end

  private

  # Absolute [start, end] pairs of the schedule blocks for the day beginning at +day_start+.
  def block_ranges(day_start)
    @schedule.blocks_for(day_start.wday).map do |start_minute, end_minute|
      [day_start + start_minute.minutes, day_start + end_minute.minutes]
    end
  end
end
