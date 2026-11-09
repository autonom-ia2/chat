# One file of a campaign import as a person downloads it (#2332). The files this app wrote go out as Excel opens them;
# the person's own upload goes out as it came. Who does not read contacts gets the names masked (#2802); the original and
# the normalized file are refused before this (CampaignImportPolicy#download_file?).
class CampaignImports::DownloadFile
  ORIGINAL = 'original'.freeze

  def initialize(campaign_import, kind, account_user)
    @campaign_import = campaign_import
    @kind = kind.to_s
    @account_user = account_user
  end

  def available?
    attachment&.attached? || false
  end

  def data
    return attachment.download if @kind == ORIGINAL

    CampaignImports::ExcelCsv.from_stored(attachment.download, mask_names: ConversationAudience::Access.hides_contact_data?(@account_user))
  end

  def filename
    attachment.blob.filename.to_s
  end

  def content_type
    attachment.blob.content_type || 'application/octet-stream'
  end

  private

  def attachment
    @attachment ||= {
      ORIGINAL => @campaign_import.original_file,
      'normalized_csv' => @campaign_import.normalized_csv,
      'error_csv' => @campaign_import.error_csv,
      'report_csv' => @campaign_import.report_csv
    }[@kind]
  end
end
