class EmailCampaigns::RecipientImportJob < ApplicationJob
  queue_as :low

  def perform(import_id)
    return unless EmailCampaigns::Config.enabled?

    import = EmailCampaignImport.find_by(id: import_id)
    return unless import

    # NOWAIT makes duplicate deliveries harmless. The row lock is released if a
    # worker dies; the recovery job can then safely rerun the atomic import.
    import.with_lock('FOR UPDATE NOWAIT') do
      return unless import.active?

      import.update!(status: :processing)
    end
    process(import)
  rescue ActiveRecord::LockWaitTimeout
    # Another delivery of this job owns the import.
    nil
  rescue StandardError => e
    Rails.logger.error("[EmailCampaigns::RecipientImportJob] import=#{import_id} error_class=#{e.class.name}")
    import&.with_lock do
      import.update!(status: :failed, error_code: error_code(e), completed_at: Time.current) if import.active?
    end
  end

  private

  def process(import)
    import.with_lock('FOR UPDATE NOWAIT') do
      return unless import.active?

      result = EmailCampaigns::RecipientImporter.new(
        import.email_campaign, import.source_file, filename: import.source_file.filename.to_s
      ).perform
      # Recipients, counters and completion commit together, or all roll back.
      import.update!(status: :completed, result: result.to_h, error_code: nil, completed_at: Time.current)
    end
  end

  def error_code(error)
    return error.message if error.is_a?(EmailCampaigns::RecipientImporter::Error)
    return 'invalid_file' if error.is_a?(ArgumentError) || error.is_a?(REXML::ParseException) || error.is_a?(CSV::MalformedCSVError)

    'import_failed'
  end
end
