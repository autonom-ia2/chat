module CampaignImports
  class Importer
    include SuppressedContactEvents

    Error = Class.new(StandardError)
    BLOCK_SIZE = 500

    def initialize(campaign_import)
      @campaign_import = campaign_import
      @account = campaign_import.account
    end

    # Rows are written in blocks, each in its own transaction, and every row in its own
    # savepoint: one bad row is marked as failed and the rest of the base still imports.
    # Rows already imported are skipped, so a retried job does not duplicate work: an import that broke midway
    # (`failed`, CampaignImport#import_resumable?) goes on from where it stopped when it runs again (#2921).
    def perform
      return unless transition_to_importing!
      return refuse_without_permission! unless contact_row.allowed?

      with_suppressed_contact_events do
        label_records = ActiveRecord::Base.transaction { ensure_labels! } unless campaign_import.spreadsheet_flow?
        contact_attributes&.prepare!
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
        validation_summary: campaign_import.validation_summary.to_h.merge(import_error: e.class.name),
        **company_counters
      )
    end

    private

    attr_reader :campaign_import, :account

    def transition_to_importing!
      should_import = false
      campaign_import.with_lock do
        campaign_import.reload
        next if campaign_import.importing? || campaign_import.completed? || campaign_import.completed_with_failures?

        raise Error, 'campaign_import_not_ready' unless startable?

        # What an earlier failure left (#2921) is no longer true once the writing starts again.
        campaign_import.update!(
          status: :importing, import_started_at: Time.current, import_finished_at: nil,
          validation_summary: campaign_import.validation_summary.to_h.except('import_error')
        )
        should_import = true
      end
      should_import
    end

    def startable? = campaign_import.queued? || campaign_import.ready_to_confirm? || campaign_import.import_resumable?

    def import_block(block, label_records)
      import_companies&.prepare(block)
      ActiveRecord::Base.transaction do
        import_rows = locked_rows(block)
        imported = block.filter_map do |row|
          import_row = import_rows.fetch(row[:row_number])
          next if import_row.status_imported?

          contact = import_one(row, import_row, label_records)
          [contact.id, row_label_titles(row, label_records)] if contact
        end
        BulkContactLabeler.new(imported).perform if label_records
      end
      # Still alive (#2921): the sweep (StalledImportsJob) reads the import's `updated_at`. After the last block
      # this is also the mark right before finish_import!.
      campaign_import.touch # rubocop:disable Rails/SkipsModelValidations -- only the timestamp moves
    end

    # The block's rows stay locked until it commits (#2921). If the same import ever runs twice at once (the sweep
    # put it back in the queue while a slow worker was still alive), the second run waits here and then finds the
    # rows already imported. Contacts have no unique index on the phone, so this is what keeps them from doubling.
    def locked_rows(block)
      campaign_import.campaign_import_rows.where(row_number: block.pluck(:row_number)).order(:row_number).lock.index_by(&:row_number)
    end

    def import_one(row, import_row, label_records)
      ActiveRecord::Base.transaction(requires_new: true) do
        written = contact_row.write(row)
        contact = written.contact
        contact_attributes&.merge!(contact, import_row.extra_values)
        destinos&.aplicar(contact, import_row.extra_values, empresa: written.company)
        import_row.assign_attributes(import_companies.row_attributes(written.company)) if import_companies
        mark_row_imported!(import_row, row, contact, written.existing, label_records)
        contact
      end
    rescue StandardError => e
      import_row.restore_attributes(%i[company_id company_result]) # the company rolled back with the row
      import_row.update!(
        status: :import_failed,
        error_messages: Array(import_row.error_messages) | ["import_failed:#{e.class.name}"] # once, however many passes
      )
      nil
    end

    # Públicos (#1005, N1) create no labels at all: label_records is nil and rows carry none.
    def row_label_titles(row, label_records)
      label_records ? [label_records[:base].title, label_records[:batches].fetch(row[:batch_index]).title] : []
    end

    # One row's contact and company (ContactRow, shared with the automation step "para_cada").
    # Importar contatos asks the Contacts screen's question of who uploaded the file; Públicos and the
    # campaign base flow keep their own (CampaignImportPolicy, at the controller).
    def contact_row
      @contact_row ||= ContactRow.new(account, account_user: importer_account_user, linker: import_companies&.linker)
    end

    def importer_account_user
      return ContactRow::UNCHECKED unless campaign_import.contact_import?

      account.account_users.find_by(user_id: campaign_import.user_id)
    end

    # Who uploaded lost the import permission (or left the account) before the job ran: nothing is
    # written and the whole import fails with the reason, as an import that broke midway does.
    def refuse_without_permission!
      campaign_import.update!(
        status: :failed, imported_contacts_count: 0, failed_contacts_count: campaign_import.valid_rows.to_i,
        import_finished_at: Time.current,
        validation_summary: campaign_import.validation_summary.to_h.merge(import_error: 'import_not_allowed')
      )
    end

    # Públicos and Importar contatos (#998, #1006): the old campaign base flow never touches companies.
    def import_companies = @import_companies ||= (ImportCompanies.new(campaign_import) if campaign_import.spreadsheet_flow?)

    # Importar contatos (#1006): extra columns become contact custom attributes.
    def contact_attributes = @contact_attributes ||= (ContactImports::CustomAttributes.new(campaign_import) if campaign_import.contact_import?)

    # Trazer minha lista (#2896): where the columns sent out of the attributes go (city, company phone, customer). nil without the mark.
    def destinos = @destinos ||= ContactImports::Trazer::DestinosDaLinha.da(campaign_import)

    def company_counters = import_companies&.counters || {}

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

    def normalized_rows = @normalized_rows ||= NormalizedRows.new(campaign_import).perform

    def mark_row_imported!(import_row, row, contact, was_existing, label_records)
      import_row.update!(
        contact_id: contact.id,
        was_existing_contact: was_existing,
        labels_applied: row_label_titles(row, label_records),
        batch_index: row[:batch_index],
        error_messages: [], # a row that failed in an earlier pass (#2921) and now went in
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
        ImportReport.new(campaign_import).attach(imported_count: imported_count, existing_count: existing_count, failed_count: failed_count)
        campaign_import.update!(
          status: failed_count.zero? ? :completed : :completed_with_failures,
          imported_contacts_count: imported_count,
          existing_contacts_count: existing_count,
          failed_contacts_count: failed_count,
          import_finished_at: Time.current,
          **company_counters, **channel_counts
        )
      end
    end

    # #1005 A1: after saving, the WhatsApp count is who the send can reach (same rule as AudienceContacts).
    def channel_counts = campaign_import.audience? ? { channels: CampaignJourney::AudienceContacts.recounted_channels(campaign_import) } : {}

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
  end
end
