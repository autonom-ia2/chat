module Crm
  module Reports
    # Cards closed over time, bucketed by day/week/month, for the selected
    # pipeline. Drives the throughput timeseries chart.
    #
    # Multifunil (#1151): won/lost only come from a funnel that counts as sale and
    # resolved/cancelled only from a service funnel, so a card won before the funnel
    # stopped counting as sale is never a sale. Each card counts once.
    class Throughput < BaseReport
      BUCKETS = { 'day' => 'day', 'week' => 'week', 'month' => 'month' }.freeze
      SALE_OUTCOMES = %w[won lost].freeze
      SERVICE_OUTCOMES = %w[resolved cancelled].freeze

      def perform
        counts = outcomes.index_with { |outcome| bucketed(outcome) }
        keys = counts.values.flat_map(&:keys).uniq.sort

        {
          group_by: bucket,
          counts_as_sale: counts_as_sale?,
          period: { since: since.iso8601, until: until_time.iso8601 },
          series: keys.map { |key| series_point(key, counts) }
        }
      end

      private

      def bucket
        BUCKETS[params[:group_by].to_s] || 'day'
      end

      def counts_as_sale?
        pipeline.blank? || pipeline.counts_as_sale?
      end

      def outcomes
        counts_as_sale? ? SALE_OUTCOMES : SERVICE_OUTCOMES
      end

      def series_point(key, counts)
        point = { date: key.to_date.iso8601 }
        (SALE_OUTCOMES + SERVICE_OUTCOMES).each { |outcome| point[outcome.to_sym] = counts.dig(outcome, key) || 0 }
        point
      end

      def closed_in_range
        scope = account.crm_cards.where(closed_at: range)
        pipeline.present? ? scope.where(pipeline_id: pipeline.id) : scope
      end

      def bucketed(outcome)
        closed_in_range.where(status: Crm::Card.statuses[outcome])
                       .group(Arel.sql("date_trunc('#{bucket}', closed_at)")).count
      end
    end
  end
end
