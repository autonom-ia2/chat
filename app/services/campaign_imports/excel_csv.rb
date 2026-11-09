require 'csv'

# The CSV a person downloads (#2332): UTF-8 BOM, so Excel shows the accents, and ";", so Excel in Portuguese opens it in
# columns (as the prospecting export, #682). Only on the way out: the normalized file is stored with "," because the
# importer reads it back.
module CampaignImports::ExcelCsv
  BOM = "\uFEFF".freeze

  module_function

  NAME_HEADER = 'name'.freeze

  # A file this app stored with "," (normalized, errors, report), as Excel opens it. Its cells were made safe when written.
  # mask_names: who downloads does not read contacts (#2802); the "name" column goes out masked.
  def from_stored(text, mask_names: false)
    rows = CSV.parse(text.dup.force_encoding(Encoding::UTF_8).delete_prefix(BOM))
    rows = with_masked_names(rows) if mask_names
    BOM + CSV.generate(col_sep: ';') { |csv| rows.each { |row| csv << row } }
  end

  def with_masked_names(rows)
    header, *body = rows
    column = header.to_a.index(NAME_HEADER)
    return rows if column.nil?

    [header] + body.map { |row| row.each_with_index.map { |cell, index| index == column ? masked(cell) : cell } }
  end

  def masked(name)
    name.presence && ConversationAudience::Access.masked_name(name)
  end
end
