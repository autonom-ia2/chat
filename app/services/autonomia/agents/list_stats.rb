class Autonomia::Agents::ListStats
  HANDOFF_EVENT_TYPES = Autonomia::Agents::AgentEvent::HANDOFF_TYPES.map do |type|
    Autonomia::Agents::AgentEvent.event_types.fetch(type)
  end.freeze
  REPLIED_EVENT_TYPE = Autonomia::Agents::AgentEvent.event_types.fetch('replied')

  def initialize(agents:, now: Time.current)
    @agents = Array(agents).to_a
    @now = now.in_time_zone
  end

  def call
    agent_ids = @agents.filter_map(&:id).uniq
    account_ids = @agents.filter_map(&:account_id).uniq
    counts = aggregate_counts(agent_ids, account_ids)

    agent_ids.index_with do |agent_id|
      row = counts.fetch(agent_id, {})
      {
        week: { replies: row.fetch(:week_replies, 0), handoffs: row.fetch(:week_handoffs, 0) },
        month: { replies: row.fetch(:month_replies, 0), handoffs: row.fetch(:month_handoffs, 0) }
      }
    end
  end

  private

  def aggregate_counts(agent_ids, account_ids)
    return {} if agent_ids.empty? || account_ids.empty?

    week_from = window_start(7)
    month_from = window_start(30)
    event_scope(account_ids, agent_ids, month_from)
      .group(:autonomia_agent_id)
      .pluck(Arel.sql(aggregate_select(week_from, month_from)))
      .to_h do |agent_id, week_replies, week_handoffs, month_replies, month_handoffs|
        [agent_id, counts_for(week_replies, week_handoffs, month_replies, month_handoffs)]
      end
  end

  def event_scope(account_ids, agent_ids, month_from)
    Autonomia::Agents::AgentEvent
      .where(account_id: account_ids, autonomia_agent_id: agent_ids, created_at: month_from..@now)
  end

  def aggregate_select(week_from, month_from)
    quoted_week = quote(week_from)
    quoted_month = quote(month_from)
    quoted_to = quote(@now)
    handoff_types = HANDOFF_EVENT_TYPES.join(', ')

    <<~SQL.squish
      autonomia_agent_id,
      COUNT(*) FILTER (WHERE event_type = #{REPLIED_EVENT_TYPE} AND created_at BETWEEN #{quoted_week} AND #{quoted_to}) AS week_replies,
      COUNT(*) FILTER (WHERE event_type IN (#{handoff_types}) AND created_at BETWEEN #{quoted_week} AND #{quoted_to}) AS week_handoffs,
      COUNT(*) FILTER (WHERE event_type = #{REPLIED_EVENT_TYPE} AND created_at BETWEEN #{quoted_month} AND #{quoted_to}) AS month_replies,
      COUNT(*) FILTER (WHERE event_type IN (#{handoff_types}) AND created_at BETWEEN #{quoted_month} AND #{quoted_to}) AS month_handoffs
    SQL
  end

  def counts_for(week_replies, week_handoffs, month_replies, month_handoffs)
    {
      week_replies: week_replies.to_i,
      week_handoffs: week_handoffs.to_i,
      month_replies: month_replies.to_i,
      month_handoffs: month_handoffs.to_i
    }
  end

  def window_start(days)
    (@now - (days - 1).days).beginning_of_day
  end

  def quote(value)
    Autonomia::Agents::AgentEvent.connection.quote(value)
  end
end
