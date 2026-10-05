require 'csv'
require 'stringio'

module CampaignImports
  class Importer
    Error = Class.new(StandardError)
    BLOCK_SIZE = 500

    def initialize(campaign_import)
      @campaign_import = campaign_import
      @account = campaign_import.account
    end

    # Rows are written in blocks, each in its own transaction, and every row in its own
    # savepoint: one bad row is marked as failed and the rest of the base still imports.
    # Rows already imported are skipped, so a retried job does not duplicate work.
    def perform
      return unless transition_to_importing!

      with_suppressed_contact_events do
        label_records = ActiveRecord::Base.transaction { ensure_labels! }
        normalized_rows.each_slice(BLOCK_SIZE) { |block| import_block(block, label_records) }
        finish_import!
      end
    rescue StandardError => e
      Rails.logger.error(
        "[CampaignImports::Importer] import_id=#{campaign_import.id} #{e.class}: #{SafeLogMessage.call(e.message)}"
      )
      imported_count = campaign_import.campaign_import_rows.status_imported.count
      campaign_import.update!(
        status: :failed,
        imported_contacts_count: imported_count,
        failed_contacts_count: campaign_import.valid_rows.to_i - imported_count,
        import_finished_at: Time.current,
        validation_summary: campaign_import.validation_summary.to_h.merge(import_error: e.class.name)
      )
    end

    private

    attr_reader :campaign_import, :account

    def transition_to_importing!
      should_import = false
      campaign_import.with_lock do
        campaign_import.reload
        next if campaign_import.importing? || campaign_import.completed? || campaign_import.completed_with_failures?

        raise Error, 'campaign_import_not_ready' unless campaign_import.queued? || campaign_import.ready_to_confirm?

        campaign_import.update!(status: :importing, import_started_at: Time.current)
        should_import = true
      end
      should_import
    end

    def with_suppressed_contact_events
      previous = Current.suppress_contact_events
      Current.suppress_contact_events = true
      yield
    ensure
      Current.suppress_contact_events = previous
    end

    def import_block(block, label_records)
      import_rows = campaign_import.campaign_import_rows.where(row_number: block.pluck(:row_number)).index_by(&:row_number)
      ActiveRecord::Base.transaction do
        imported = block.filter_map do |row|
          import_row = import_rows.fetch(row[:row_number])
          next if import_row.status_imported?

          contact = import_one(row, import_row, label_records)
          [contact.id, row_label_titles(row, label_records)] if contact
        end
        BulkContactLabeler.new(imported).perform
      end
    end

    def import_one(row, import_row, label_records)
      ActiveRecord::Base.transaction(requires_new: true) do
        contact = find_existing_contact(row[:phone_number])
        was_existing = contact.present?
        contact ||= account.contacts.create!(name: row[:name], phone_number: row[:phone_number])
        contact.update!(name: row[:name]) if contact.name.blank? && row[:name].present?
        mark_row_imported!(import_row, row, contact, was_existing, label_records)
        contact
      end
    rescue StandardError => e
      import_row.update!(
        status: :import_failed,
        error_messages: Array(import_row.error_messages) + ["import_failed:#{e.class.name}"]
      )
      nil
    end

    def row_label_titles(row, label_records)
      [label_records[:base].title, label_records[:batches].fetch(row[:batch_index]).title]
    end

    def find_existing_contact(phone_number)
      @contact_matcher ||= ContactMatcher.new(account)
      @contact_matcher.find(phone_number)
    end

    def ensure_labels!
      base_import_label = campaign_import.campaign_import_labels.kind_base.first!
      batch_import_labels = campaign_import.campaign_import_labels.kind_batch.index_by(&:batch_index)

      base_label = ensure_label_record!(base_import_label)
      batch_labels = batch_import_labels.transform_values { |import_label| ensure_label_record!(import_label) }
      { base: base_label, batches: batch_labels }
    end

    def ensure_label_record!(campaign_import_label)
      label = account.labels.find_or_initialize_by(title: campaign_import_label.title)
      raise Error, 'label_collision_visible_on_sidebar' if label.persisted? && label.show_on_sidebar?

      label.assign_attributes(show_on_sidebar: false) unless label.persisted?
      label.save!
      campaign_import_label.update!(label_id: label.id)
      label
    end

    def normalized_rows
      @normalized_rows ||= begin
        raise Error, 'normalized_csv_missing' unless campaign_import.normalized_csv.attached?

        csv_data = campaign_import.normalized_csv.download
        CSV.parse(csv_data, headers: true).map do |row|
          normalized = PhoneNormalizer.normalize!(row['phone_number'])
          {
            row_number: row['row_number'].to_i,
            name: row['name'].to_s.strip,
            phone_number: normalized.phone_number,
            phone_hash: normalized.hash,
            batch_index: row['batch_index'].to_i
          }
        end
      end
    end

    def mark_row_imported!(import_row, row, contact, was_existing, label_records)
      import_row.update!(
        contact_id: contact.id,
        was_existing_contact: was_existing,
        labels_applied: row_label_titles(row, label_records),
        batch_index: row[:batch_index],
        status: :imported
      )
    end

    def finish_import!
      rows = campaign_import.campaign_import_rows
      imported_count = rows.status_imported.count
      existing_count = rows.status_imported.where(was_existing_contact: true).count
      failed_count = rows.status_import_failed.count

      ActiveRecord::Base.transaction do
        update_label_counts!
        attach_report_csv(imported_count, existing_count, failed_count)
        campaign_import.update!(
          status: failed_count.zero? ? :completed : :completed_with_failures,
          imported_contacts_count: imported_count,
          existing_contacts_count: existing_count,
          failed_contacts_count: failed_count,
          import_finished_at: Time.current
        )
      end
    end

    def update_label_counts!
      campaign_import.campaign_import_labels.find_each do |import_label|
        count = if import_label.kind_base?
                  campaign_import.campaign_import_rows.status_imported.count
                else
                  campaign_import.campaign_import_rows.status_imported.where(batch_index: import_label.batch_index).count
                end
        import_label.update!(applied_count: count)
      end
    end

    def attach_report_csv(imported_count, existing_count, failed_count)
      rows = [
        { 'metric' => 'status', 'value' => failed_count.zero? ? 'completed' : 'completed_with_failures' },
        { 'metric' => 'imported_contacts_count', 'value' => imported_count },
        { 'metric' => 'existing_contacts_count', 'value' => existing_count },
        { 'metric' => 'created_contacts_count', 'value' => imported_count - existing_count },
        { 'metric' => 'failed_contacts_count', 'value' => failed_count },
        { 'metric' => 'base_label', 'value' => campaign_import.base_label },
        { 'metric' => 'batch_count', 'value' => campaign_import.batch_count }
      ]

      campaign_import.report_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(%w[metric value], rows)),
        filename: report_filename,
        content_type: 'text/csv'
      )
    end

    def report_filename
      basename = campaign_import.source_filename.to_s.sub(/\.[^.]*\z/, '').presence || "campaign_import_#{campaign_import.id}"
      "#{basename}_report.csv"
    end
  end
end
