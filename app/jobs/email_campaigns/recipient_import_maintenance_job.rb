class EmailCampaigns::RecipientImportMaintenanceJob < ApplicationJob
  queue_as :housekeeping

  def perform
    return unless EmailCampaigns::Config.enabled?

    # Also recovers a crash between committing the upload and enqueueing its job.
    EmailCampaignImport.active.where(updated_at: ...EmailCampaignImport::RECOVERY_AFTER.ago).find_each do |import|
      recover(import)
    end
    EmailCampaignImport.where(status: [:completed, :failed]).where(created_at: ...EmailCampaignImport::RETENTION.ago)
                       .with_attached_source_file.find_each do |import|
      import.source_file.purge_later if import.source_file.attached?
    end
  end

  private

  def recover(import)
    enqueue = false
    import.with_lock('FOR UPDATE NOWAIT') do
      return unless import.active? && import.updated_at < EmailCampaignImport::RECOVERY_AFTER.ago

      if import.created_at < EmailCampaignImport::RETENTION.ago
        import.update!(status: :failed, error_code: 'file_expired', completed_at: Time.current)
      else
        import.update!(updated_at: Time.current)
        enqueue = true
      end
    end
    # The worker uses NOWAIT. Enqueue only after the transaction releases its
    # lock, otherwise a fast worker can mistake maintenance for a live worker.
    EmailCampaigns::RecipientImportJob.perform_later(import.id) if enqueue
  rescue ActiveRecord::LockWaitTimeout
    # A live worker still owns the import; do not expire or enqueue it.
    nil
  end
end
