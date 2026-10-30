module Crm
  module Reports
    # Shared scoping for CRM report builders: account, selected pipeline
    # (single-pipeline funnel/value with a mandatory selector, default =
    # is_default) and the analysis time window.
    #
    # #1876: o relógio dos relatórios é o fuso da conta (Crm::Timezone::Resolver), nunca o do servidor. Vale para o
    # período padrão, para a data sem fuso que chega no parâmetro, para o dia/semana/mês do gráfico de fechados
    # (Throughput) e para o mês da meta (Summary). O gráfico de uso de IA (AiUsage) ainda corta o dia em UTC.
    class BaseReport
      DEFAULT_RANGE_DAYS = 30
      MAX_RANGE_DAYS = 366

      # pipelines: os funis que a pessoa enxerga (acesso por funil, #1148, PR D); sem restrição, os ativos da conta (funil
      # arquivado sai dos relatórios, como das Metas).
      # value_visible: false tira os valores de venda em R$ de quem não tem `sales_value_view` (#2075); contagens ficam.
      def initialize(account:, params: {}, pipelines: nil, value_visible: true)
        @account = account
        @params = params || {}
        @pipelines = pipelines || account.crm_pipelines.active
        @value_visible = value_visible
      end

      def perform
        raise NotImplementedError
      end

      private

      attr_reader :account, :params, :pipelines

      def value_visible?
        @value_visible
      end

      def pipeline
        @pipeline ||= pipelines.find_by(id: params[:pipeline_id]) || default_pipeline
      end

      def default_pipeline
        pipelines.find_by(is_default: true) ||
          pipelines.order(:position, :id).first
      end

      def zone
        @zone ||= Crm::Timezone::Resolver.new(account: account).zone_or_default
      end

      def now
        zone.now
      end

      def since
        @since ||= parse_time(params[:since]) || (now - DEFAULT_RANGE_DAYS.days).beginning_of_day
      end

      def until_time
        @until_time ||= clamp_until(parse_time(params[:until]) || now)
      end

      def range
        since..until_time
      end

      def parse_time(value, in_zone: zone)
        return if value.blank?

        in_zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # Guard against unbounded scans: cap the window length.
      def clamp_until(value)
        max = since + MAX_RANGE_DAYS.days
        value > max ? max : value
      end

      # nil quando a pessoa não vê valores de venda (#2075).
      def currency_amount(scope)
        return unless value_visible?

        scope.group(:currency).sum(:value_cents).map do |currency, cents|
          { currency: currency, value_cents: cents }
        end
      end
    end
  end
end
