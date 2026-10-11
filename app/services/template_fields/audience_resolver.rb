# publico.<coluna> (#1331): a linha da planilha do Público (`campaign_import_rows.extra_values`), formatada pelo tipo
# da coluna (`schema_resolution['extra_columns']`, CampaignImports::ColumnTypes). Coluna sem tipo vai como está.
class TemplateFields::AudienceResolver
  # columns: os cabeçalhos das colunas extras; values: { cabeçalho => valor } da linha; types: { cabeçalho => tipo }.
  def initialize(columns:, values:, types: {})
    @columns = Array(columns).map(&:to_s)
    @values = values.to_h
    @types = types.to_h
  end

  def keys
    @columns.map { |column| TemplateFields::Catalog.audience_key(column) }
  end

  def value(key)
    key = key.to_s
    return unless TemplateFields::Catalog.audience_key?(key)

    column = TemplateFields::Catalog.audience_column(key)
    return unless @columns.include?(column)

    TemplateFields::Format.audience_value(@values[column], TemplateFields::Catalog.type(key, column_types: @types))
  end
end
