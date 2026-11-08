module Crm
  module Reports
    # No-show analytics for meetings whose outcome was recorded within the
    # selected period. Provider-agnostic (outcome is CRM-internal). The no-show
    # rate is held/no_show over the decided total.
    class Meetings < BaseReport
      def perform
        return empty_payload if pipeline.blank?

        # Scope to the selected pipeline (consistent with every other dashboard
        # KPI) — meetings whose card belongs to this pipeline, outcome recorded
        # in the period.
        recorded = account.crm_meetings.with_outcome
                          .where(card_id: pipeline_card_ids)
                          .where(outcome_recorded_at: range)
        held = recorded.outcome_held.count
        no_show = recorded.outcome_no_show.count
        decided = held + no_show

        {
          period: { since: since.iso8601, until: until_time.iso8601 },
          held: held,
          no_show: no_show,
          no_show_rate: decided.zero? ? 0 : (no_show.to_f / decided).round(4)
        }
      end

      # Public so the controller returns the SAME shape (incl. period) for
      # disabled accounts — no contract drift between enabled/disabled.
      def empty_payload
        {
          period: { since: since.iso8601, until: until_time.iso8601 },
          held: 0, no_show: 0, no_show_rate: 0
        }
      end

      private

      def pipeline_card_ids
        Crm::Relacao.cards_do_funil(account).where(pipeline_id: pipeline.id).select(:id)
      end
    end
  end
end
