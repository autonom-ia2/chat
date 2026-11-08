module Crm
  module Reports
    # Snapshot of OPEN cards distributed across the stages of a single pipeline
    # (mandatory selector; default = is_default). Count + value by currency per
    # stage so different currencies are never summed together.
    class Funnel < BaseReport
      def perform
        return empty if pipeline.blank?

        stages = pipeline.stages.order(:position, :id).to_a
        counts = open_cards.group(:stage_id).count
        # Valor de venda (#2075): sem `sales_value_view`, value_by_currency vem nil e a contagem fica.
        values = value_visible? ? open_cards.group(:stage_id, :currency).sum(:value_cents) : nil

        {
          pipeline: { id: pipeline.id, name: pipeline.name },
          value_hidden: !value_visible?,
          stages: stages.map { |stage| stage_entry(stage, counts, values) }
        }
      end

      private

      def empty
        { pipeline: nil, stages: [] }
      end

      def open_cards
        Crm::Relacao.cards_do_funil(account).where(pipeline_id: pipeline.id, status: Crm::Card.statuses[:open])
      end

      def stage_entry(stage, counts, values)
        {
          id: stage.id,
          name: stage.name,
          position: stage.position,
          color: stage.color,
          count: counts[stage.id] || 0,
          value_by_currency: values && stage_values(stage, values)
        }
      end

      def stage_values(stage, values)
        values.select { |(stage_id, _currency), _cents| stage_id == stage.id }
              .map { |(_stage_id, currency), cents| { currency: currency, value_cents: cents } }
      end
    end
  end
end
