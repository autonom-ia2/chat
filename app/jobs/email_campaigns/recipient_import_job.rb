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
    importer = EmailCampaigns::RecipientImporter.new(
      import.email_campaign, import.source_file, filename: import.source_file.filename.to_s, import: import
    ).prepare
    # Reserve the parent FK before the import row. This branch only inserts
    # children: it must not acquire account/state or update campaign until commit.
    import.email_campaign.with_lock('FOR KEY SHARE') do
      import.with_lock('FOR UPDATE NOWAIT') do
        next unless import.active?

        result = importer.perform
        # Recipients/issues/completion remain atomic. Counters wait for commit.
        import.update!(status: :completed, result: result.to_h, error_code: nil, completed_at: Time.current)
      end
    end
  end

  def error_code(error)
    return error.message if error.is_a?(EmailCampaigns::RecipientImporter::Error)
    return 'invalid_file' if error.is_a?(ArgumentError) || error.is_a?(REXML::ParseException) || error.is_a?(CSV::MalformedCSVError)

    'import_failed'
  end
end
