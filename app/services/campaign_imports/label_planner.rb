module CampaignImports
  class LabelPlanner
    Error = Class.new(StandardError)
    Plan = Struct.new(:base_label, :batch_labels, :batch_sizes, :batch_indexes, keyword_init: true)

    def initialize(campaign_import, total_rows:)
      @campaign_import = campaign_import
      @total_rows = total_rows.to_i
    end

    def perform
      validate!

      plan = build_plan
      persist_plan(plan)
      plan
    end

    private

    attr_reader :campaign_import, :total_rows

    def validate!
      raise Error, 'empty_file' unless total_rows.positive?
      raise Error, 'too_many_batches' if requested_batch_count > CampaignImports::Config.max_batches
      raise Error, 'batch_count_exceeds_rows' if requested_batch_count > total_rows
    end

    def build_plan
      base_label = build_base_label
      sizes = batch_sizes
      batch_labels = sizes.each_with_index.map do |size, index|
        {
          title: "#{base_label}_lote_#{index + 1}",
          batch_index: index,
          planned_count: size
        }
      end

      Plan.new(
        base_label: base_label,
        batch_labels: batch_labels,
        batch_sizes: sizes,
        batch_indexes: batch_indexes(sizes)
      )
    end

    def persist_plan(plan)
      campaign_import.campaign_import_labels.destroy_all
      campaign_import.campaign_import_labels.create!(
        title: plan.base_label,
        kind: :base,
        planned_count: total_rows,
        applied_count: 0
      )
      plan.batch_labels.each do |label|
        campaign_import.campaign_import_labels.create!(
          title: label[:title],
          kind: :batch,
          batch_index: label[:batch_index],
          planned_count: label[:planned_count],
          applied_count: 0
        )
      end

      campaign_import.update!(
        campaign_slug: campaign_slug,
        base_label: plan.base_label,
        batch_count: requested_batch_count,
        labels_payload: {
          base_label: plan.base_label,
          batch_labels: plan.batch_labels,
          batch_sizes: plan.batch_sizes
        }
      )
    end

    # Spreads rows as evenly as possible: every batch gets the base size and the
    # first `remainder` batches get one extra row, so no batch is ever empty.
    def batch_sizes
      base_size, remainder = total_rows.divmod(requested_batch_count)
      Array.new(requested_batch_count) { |index| base_size + (index < remainder ? 1 : 0) }
    end

    def batch_indexes(sizes)
      sizes.each_with_index.flat_map { |size, index| Array.new(size, index) }
    end

    def requested_batch_count
      @requested_batch_count ||= [campaign_import.batch_count.to_i, 1].max
    end

    def build_base_label
      "campanha_#{campaign_slug}_#{campaign_import.id}"
    end

    def campaign_slug
      @campaign_slug ||= begin
        raw_name = campaign_import.campaign_name.presence || campaign_import.source_filename.presence || 'campanha'
        I18n.transliterate(raw_name)
            .downcase
            .gsub(/[^a-z0-9]+/, '_')
            .gsub(/\A_+|_+\z/, '')
            .presence
            .then { |slug| (slug || 'campanha')[0, 80] }
      end
    end
  end
end
