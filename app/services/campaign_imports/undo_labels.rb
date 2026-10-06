module CampaignImports
  class UndoLabels
    include SuppressedContactEvents

    def initialize(campaign_import)
      @campaign_import = campaign_import
      @account = campaign_import.account
    end

    def perform
      return unless transition_to_undoing!

      with_suppressed_contact_events do
        ActiveRecord::Base.transaction do
          campaign_import.campaign_import_rows.where.not(contact_id: nil).find_each do |import_row|
            contact = account.contacts.find_by(id: import_row.contact_id)
            next if contact.blank?

            Array(import_row.labels_applied).each { |label| contact.label_list.remove(label) }
            contact.save!
            import_row.update!(status: :labels_undone)
          end

          campaign_import.campaign_import_labels.update_all(applied_count: 0, updated_at: Time.current)
          campaign_import.update!(status: :labels_undone, undo_status: :completed, undo_finished_at: Time.current)
        end
      end
    rescue StandardError
      campaign_import.update!(status: :undo_failed, undo_status: :failed, undo_finished_at: Time.current)
    end

    private

    attr_reader :campaign_import, :account

    def transition_to_undoing!
      should_undo = false
      campaign_import.with_lock do
        campaign_import.reload
        next if campaign_import.labels_undone?

        if campaign_import.undoing_labels?
          should_undo = true
          next
        end

        raise StandardError, 'campaign_import_undo_not_available' unless campaign_import.completed? || campaign_import.completed_with_failures?

        campaign_import.update!(status: :undoing_labels, undo_status: :processing, undo_started_at: Time.current)
        should_undo = true
      end
      should_undo
    end
  end
end
