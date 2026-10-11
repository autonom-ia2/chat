module Crm
  module Reports
    # Shared scoping for CRM report builders: account, selected pipeline
    # (single-pipeline funnel/value with a mandatory selector, default =
    # is_default) and the analysis time window.
    class BaseReport
      DEFAULT_RANGE_DAYS = 30
      MAX_RANGE_DAYS = 366

      # pipelines: os funis que a pessoa enxerga (acesso por funil, #1148, PR D); sem restrição, todos os da conta.
      def initialize(account:, params: {}, pipelines: nil)
        @account = account
        @params = params || {}
        @pipelines = pipelines || account.crm_pipelines
      end

      def perform
        raise NotImplementedError
      end

      private

      attr_reader :account, :params, :pipelines

      def pipeline
        @pipeline ||= pipelines.find_by(id: params[:pipeline_id]) || default_pipeline
      end

      def default_pipeline
        pipelines.find_by(is_default: true) ||
          pipelines.order(:position, :id).first
      end

      def since
        @since ||= parse_time(params[:since]) || DEFAULT_RANGE_DAYS.days.ago.beginning_of_day
      end

      def until_time
        @until_time ||= clamp_until(parse_time(params[:until]) || Time.current)
      end

      def range
        since..until_time
      end

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # Guard against unbounded scans: cap the window length.
      def clamp_until(value)
        max = since + MAX_RANGE_DAYS.days
        value > max ? max : value
      end

      def currency_amount(scope)
        scope.group(:currency).sum(:value_cents).map do |currency, cents|
          { currency: currency, value_cents: cents }
        end
      end
    end
  end
end
