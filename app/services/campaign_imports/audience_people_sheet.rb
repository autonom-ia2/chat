# "Baixar lista" of an audience (#2332): who it holds, as an Excel file (.xlsx, caxlsx, as the CRM list and the
# prospecting export, #682). Phone and e-mail come from the contact (the rows keep them only masked), then the company
# and the extra columns of the audience (cidade, atributos...). Spreadsheet or conversations alike.
# contact_ids narrows it to who the viewer may see (an audience built from the conversations, #2277); nil is everyone.
# Every cell goes as text and escape_formulas keeps a "=..." name from running as a formula.
class CampaignImports::AudiencePeopleSheet
  TABLE_STYLE = { name: 'TableStyleLight1', show_row_stripes: false }.freeze

  def initialize(campaign_import, contact_ids: nil)
    @campaign_import = campaign_import
    @contact_ids = contact_ids
  end

  def to_xlsx
    package.to_stream.read
  end

  def filename
    "#{@campaign_import.name.to_s.parameterize.presence || "publico-#{@campaign_import.id}"}.xlsx"
  end

  # The built package, exposed so the specs can validate it against the format's schema.
  def package
    lines = [headers] + rows.map { |row| line(row) }
    Axlsx::Package.new.tap do |pack|
      header = pack.workbook.styles.add_style(b: true)
      pack.workbook.add_worksheet(name: I18n.t('campaign_import.people_sheet.sheet')) do |sheet|
        lines.each_with_index do |values, index|
          sheet.add_row(values, types: values.map { :string }, style: index.zero? ? header : nil, escape_formulas: true)
        end
        add_table(sheet, lines)
      end
    end
  end

  private

  # A table gives the header its filter buttons. Excel refuses a table with only the header, so it spans an empty row.
  def add_table(sheet, lines)
    last_row = [lines.size, 2].max
    sheet.add_table("A1:#{Axlsx.col_ref(lines.first.size - 1)}#{last_row}", name: 'Publico', style_info: TABLE_STYLE)
  end

  def headers
    %w[name phone email company].map { |key| I18n.t("campaign_import.people_sheet.#{key}") } + extra_columns
  end

  def extra_columns
    @extra_columns ||= Array(@campaign_import.extra_columns).map(&:to_s)
  end

  def line(row)
    contact = row.contact
    values = row.extra_values.to_h
    [contact.name, contact.phone_number, contact.email, company(row)] + extra_columns.map { |header| values[header]&.to_s }
  end

  # The same company the panel shows: the contact's, the one the row brought, the one the contact was saved with.
  def company(row)
    row.contact.try(:company)&.name.presence || row.company_name.presence || row.contact.additional_attributes.to_h['company_name']
  end

  def rows
    scope = @campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil).includes(:contact)
    scope = scope.includes(contact: :company) if Contact.reflect_on_association(:company)
    scope = scope.where(contact_id: @contact_ids.to_a) if @contact_ids
    scope.sort_by { |row| [row.contact.name.to_s.downcase, row.contact_id] }.uniq(&:contact_id)
  end
end
