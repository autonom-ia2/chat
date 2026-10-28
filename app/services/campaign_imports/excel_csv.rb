require 'csv'

# The CSV a person downloads (#2332): UTF-8 BOM, so Excel shows the accents, and ";", so Excel in Portuguese opens it in
# columns (as the prospecting export, #682). Only on the way out: the normalized file is stored with "," because the
# importer reads it back.
module CampaignImports::ExcelCsv
  BOM = "\uFEFF".freeze

  module_function

  # A file this app stored with "," (normalized, errors, report), as Excel opens it. Its cells were made safe when written.
  def from_stored(text)
    rows = CSV.parse(text.dup.force_encoding(Encoding::UTF_8).delete_prefix(BOM))
    BOM + CSV.generate(col_sep: ';') { |csv| rows.each { |row| csv << row } }
  end
end
