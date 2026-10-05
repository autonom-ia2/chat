require 'csv'

# The rows the validator approved, read back from the import's normalized CSV for the Importer.
# Phones are normalized again so the importer works with the canonical number and its hash.
class CampaignImports::NormalizedRows
  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  def perform
    raise CampaignImports::Importer::Error, 'normalized_csv_missing' unless @campaign_import.normalized_csv.attached?

    # The blob comes back as binary; the CSV was written as UTF-8 (accented names and companies).
    csv_data = @campaign_import.normalized_csv.download.force_encoding(Encoding::UTF_8)
    CSV.parse(csv_data, headers: true).map { |row| row_for(row) }
  end

  private

  def row_for(row)
    normalized = row['phone_number'].present? ? CampaignImports::PhoneNormalizer.normalize!(row['phone_number']) : nil
    {
      row_number: row['row_number'].to_i,
      name: row['name'].to_s.strip,
      phone_number: normalized&.phone_number,
      phone_hash: normalized&.hash,
      email: row['email'].presence,
      company_name: row['company_name'].presence,
      batch_index: row['batch_index'].to_i
    }
  end
end
