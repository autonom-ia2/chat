module Crm
  module Reports
    # Headline KPIs for the selected pipeline over the period: won/lost counts
    # (via closed_at), won value by currency, open pipeline value by currency,
    # and win rate. Currencies are never summed together.
    #
    # Multifunil (#1151): only a funnel that counts as sale has won/lost, win rate
    # and goal; a service funnel reports resolved/cancelled instead, and a card won
    # before the funnel stopped counting as sale never shows up as a sale. Open work
    # is counted three ways, since one conversation can hold several cards.
    class Summary < BaseReport
      def perform
        return empty if pipeline.blank?

        base_payload.merge(outcome_payload).merge(open_payload)
      end

      private

      def empty
        { pipeline: nil }
      end

      def base_payload
        {
          pipeline: { id: pipeline.id, name: pipeline.name },
          period: { since: since.iso8601, until: until_time.iso8601 },
          counts_as_sale: pipeline.counts_as_sale?
        }
      end

      def outcome_payload
        sale = pipeline.counts_as_sale?
        won = closed_with(sale ? :won : nil)
        lost = closed_with(sale ? :lost : nil)

        {
          won_count: won.count,
          lost_count: lost.count,
          win_rate: win_rate(won.count, lost.count),
          win_rate_by_value: win_rate_by_value(won, lost),
          won_value_by_currency: currency_amount(won),
          lost_value_by_currency: currency_amount(lost),
          resolved_count: closed_with(sale ? nil : :resolved).count,
          cancelled_count: closed_with(sale ? nil : :cancelled).count,
          goal: sale ? goal_payload : nil
        }
      end

      # One conversation can hold several cards (#1141): cards, conversations and
      # people are counted apart so 3 cards in 1 conversation read as 1 person.
      def open_payload
        {
          open_count: open_cards.count,
          open_conversations_count: open_conversations_count,
          open_people_count: open_cards.where.not(contact_id: nil).distinct.count(:contact_id),
          open_value_by_currency: currency_amount(open_cards)
        }
      end

      def pipeline_cards
        account.crm_cards.where(pipeline_id: pipeline.id)
      end

      def open_cards
        pipeline_cards.where(status: Crm::Card.statuses[:open])
      end

      # Primary conversation plus every linked one; UNION drops the repeats in the database.
      def open_conversations_count
        primary = open_cards.where.not(conversation_id: nil).select(:conversation_id).to_sql
        linked = Crm::CardConversation.where(account_id: account.id, card_id: open_cards.select(:id)).select(:conversation_id).to_sql
        Crm::Card.connection.select_value("SELECT COUNT(*) FROM (#{primary} UNION #{linked}) AS open_conversations").to_i
      end

      def closed_with(status)
        return pipeline_cards.none if status.nil?

        pipeline_cards.where(closed_at: range, status: Crm::Card.statuses[status])
      end

      def win_rate(won_count, lost_count)
        decided = won_count + lost_count
        decided.zero? ? nil : (won_count.to_f / decided).round(4)
      end

      # Value-weighted win rate = won_value / (won_value + lost_value). This is a
      # dimensionless ratio, so we sum value_cents across currencies for the
      # headline number (the per-currency money totals stay split elsewhere).
      def win_rate_by_value(won, lost)
        won_value = won.sum(:value_cents)
        lost_value = lost.sum(:value_cents)
        decided_value = won_value + lost_value
        return if decided_value.zero?

        (won_value.to_f / decided_value).round(4)
      end

      # Sales target attainment for the CURRENT month (a quota is monthly,
      # independent of the dashboard period selector). Returns nil when no goal
      # is set. `month_elapsed` powers the pacing indicator (attainment vs time).
      def goal_payload
        config = (pipeline.metadata || {})['goals']
        return if config.blank?

        target = config['monthly_target_cents'].to_i
        return if target.zero?

        currency = config['currency'].presence || 'BRL'
        month_start = Time.current.beginning_of_month
        achieved = pipeline_cards.where(status: Crm::Card.statuses[:won])
                                 .where(currency: currency)
                                 .where(closed_at: month_start..Time.current)
                                 .sum(:value_cents)
        month_span = Time.current.end_of_month - month_start

        {
          target_cents: target,
          currency: currency,
          achieved_cents: achieved,
          attainment: (achieved.to_f / target).round(4),
          month_elapsed: month_span.zero? ? 0 : ((Time.current - month_start) / month_span).round(4),
          month_label: month_start.strftime('%m/%Y')
        }
      end
    end
  end
end
