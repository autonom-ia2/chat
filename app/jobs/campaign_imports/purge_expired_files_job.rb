class CampaignImports::PurgeExpiredFilesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    purge_original_files
    purge_generated_files
    ContactImports::Trazer::AnexosVencidos.new.call
  end

  private

  def purge_original_files
    purge_attachment(:original_file, CampaignImports::Config.original_file_retention)
  end

  def purge_generated_files
    %i[normalized_csv error_csv report_csv].each do |attachment_name|
      purge_attachment(attachment_name, CampaignImports::Config.generated_file_retention)
    end
  end

  def purge_attachment(attachment_name, retention)
    ActiveStorage::Attachment.where(record_type: 'CampaignImport', name: attachment_name.to_s)
                             .where('created_at < ?', retention.ago)
                             .includes(:record)
                             .find_each do |attachment_record|
      campaign_import = attachment_record.record
      next unless campaign_import

      attachment = campaign_import.public_send(attachment_name)
      attachment.purge_later if attachment.attached?
    end
  end
end
