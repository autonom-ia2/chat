# The single SLA clock (issue #283). The deadline shown on the conversation card and on the
# Kanban (AppliedSla#calculate_due_at) and the instant Sla::EvaluateAppliedSlaService records
# a breach both come from #deadline, so they can never disagree.
#
# For policies with only_during_business_hours the fork calendar wins when one is usable
# (Sla::ScheduleResolver: assigned agent > inbox; several blocks per day; own timezone),
# otherwise the upstream inbox working hours apply through Sla::BusinessHoursService,
# unchanged. 24/7 policies use the wall clock.
#
# An instance is meant to live for one call chain (one serialization or one evaluation):
# the schedule and the working-hours lookups run at most once per instance.
class Sla::DueAtCalculator
  def initialize(conversation:, sla_policy:)
    @conversation = conversation
    @sla_policy = sla_policy
  end

  # Epoch seconds, or nil when the deadline is not reachable within the calculator horizon.
  def deadline(start_time, threshold_seconds)
    return (start_time + threshold_seconds.to_i.seconds).to_i unless @sla_policy.only_during_business_hours?
    return business_time_calculator.deadline(start_time, threshold_seconds)&.to_i if schedule.present?

    Sla::BusinessHoursService.new(
      inbox: @conversation.inbox,
      start_time: start_time,
      threshold_seconds: threshold_seconds,
      working_hours_by_day_cache: working_hours_by_day_cache
    ).deadline.to_i
  end

  private

  # nil is a valid resolution (no usable calendar), hence the defined? guard.
  def schedule
    @schedule = Sla::ScheduleResolver.for_conversation(@conversation) unless defined?(@schedule)
    @schedule
  end

  def business_time_calculator
    @business_time_calculator ||= Sla::BusinessTimeCalculator.new(schedule: schedule)
  end

  def working_hours_by_day_cache
    @working_hours_by_day_cache ||= @conversation.inbox.working_hours.index_by(&:day_of_week)
  end
end
