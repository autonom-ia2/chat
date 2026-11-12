require 'stringio'

# The report file of an import that ended: its final status and counts, attached to the import as a CSV
# (`report_csv`). The Importer writes it when it finishes; a later pass replaces the one before.
class CampaignImports::ImportReport
  HEADERS = %w[metric value].freeze

  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  def attach(imported_count:, existing_count:, failed_count:)
    rows = [
      { 'metric' => 'status', 'value' => failed_count.zero? ? 'completed' : 'completed_with_failures' },
      { 'metric' => 'imported_contacts_count', 'value' => imported_count },
      { 'metric' => 'existing_contacts_count', 'value' => existing_count },
      { 'metric' => 'created_contacts_count', 'value' => imported_count - existing_count },
      { 'metric' => 'failed_contacts_count', 'value' => failed_count },
      { 'metric' => 'base_label', 'value' => @campaign_import.base_label },
      { 'metric' => 'batch_count', 'value' => @campaign_import.batch_count }
    ]
    @campaign_import.report_csv.attach(
      io: StringIO.new(CampaignImports::CsvSanitizer.generate(HEADERS, rows)), filename: filename, content_type: 'text/csv'
    )
  end

  private

  # The uploaded file's name without its extension (what comes after the last dot).
  def filename
    name = @campaign_import.source_filename.to_s
    last_dot = name.rindex('.')
    basename = (last_dot ? name[0...last_dot] : name).presence || "campaign_import_#{@campaign_import.id}"
    "#{basename}_report.csv"
  end
end
