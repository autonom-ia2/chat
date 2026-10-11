# Message variables of a journey campaign (#1005, PRD §6.3 and B1b). Each template variable is
# bound to a contact field, an audience column (campaign_import_rows.extra_values), a fixed text or
# a key of the field catalog (TemplateFields::Catalog, #1331), and/or has a default used when the
# person has no value:
#
#   bindings: { '1' => { 'source' => 'field',   'value' => 'cliente.primeiro_nome' },
#               '2' => { 'source' => 'field',   'value' => 'publico.Vencimento' },
#               '3' => { 'source' => 'fixed',   'value' => 'Equipe Hub2You' } }
#   defaults: { '2' => 'em breve' }   # a default alone works as a fixed text
#
# The older sources stay valid and read through the same catalog: 'contact' (name → cliente.nome,
# first_name → cliente.primeiro_nome, company → empresa_cliente.nome) and 'column' (the raw cell,
# as before). A 'field' binding accepts the keys an audience fills (TemplateFields::Catalog.in_audience?):
# cliente.*, empresa_cliente.*, minha_empresa.* and publico.<column>, the column formatted by its
# type (column_types, CampaignImports::ColumnTypes).
#
# Keys are the template body variables, positional ('1') or named ('nome'), plus 'header.N' for a
# TEXT header and 'button.I' for a URL button (#993, CampaignJourney::TemplateVariableKeys). Every variable of the
# approved template needs a binding or a default; keys the template does not have are refused.
# Values are squished (line breaks, tabs and repeated spaces become one space): Meta refuses
# template parameters with them. A person without a value and without a default stays out with
# the reason "falta {{2}}".
class CampaignJourney::VariableBindings
  class Error < StandardError
    attr_reader :details

    def initialize(code, details = {})
      @details = details
      super(code)
    end
  end

  SOURCES = %w[contact column fixed field].freeze
  CONTACT_FIELDS = { 'name' => 'cliente.nome', 'first_name' => 'cliente.primeiro_nome', 'company' => 'empresa_cliente.nome' }.freeze
  # Catalog keys the audience coverage checks against the spreadsheet row (CampaignImports::VariableCoverage).
  COVERAGE_FIELDS = { 'cliente.nome' => 'name', 'cliente.primeiro_nome' => 'name', 'empresa_cliente.nome' => 'company' }.freeze
  MAX_VARIABLES = 20
  MAX_KEY_LENGTH = 50
  MAX_TEXT_LENGTH = 1024

  attr_reader :bindings, :defaults

  # column_types: { 'Vencimento' => 'data' } of the audience (CampaignImports::ColumnTypes.stored).
  def initialize(bindings, defaults = {}, column_types: {})
    @bindings = bindings.to_h.to_h { |key, bound| [key.to_s, bound.to_h.stringify_keys.slice('source', 'value')] }
    @defaults = defaults.to_h.to_h { |key, text| [key.to_s, text.to_s.squish] }.compact_blank
    @column_types = column_types.to_h
  end

  def any?
    keys.any?
  end

  def keys
    (bindings.keys + defaults.keys).uniq
  end

  # Checked when the campaign is created: the template variables, known sources and contact
  # fields, non-blank fixed text, and columns that exist in the audience
  # (CampaignImports::VariableCoverage, #992).
  def validate!(campaign_import, template_keys:)
    raise Error, 'invalid_variable_bindings' unless valid_shape?

    unknown = keys - template_keys
    missing = template_keys - keys
    raise Error.new('invalid_variable_bindings', unknown: unknown, missing: missing) if unknown.any? || missing.any?

    CampaignImports::VariableCoverage.new(campaign_import, mapping: coverage_mapping, defaults: defaults).perform
  rescue CampaignImports::VariableCoverage::Error
    raise Error.new('invalid_variable_bindings', unknown_columns: unknown_columns(campaign_import))
  end

  # => [{ '1' => 'Ana', '2' => '10/2026' }, []] or [{ ... }, ['2']] when a value is missing.
  def resolve(contact, extra_values)
    fields = field_resolver(contact, extra_values.to_h)
    values = keys.to_h do |key|
      bound = bindings[key]
      [key, (bound && value_for(bound, fields, extra_values.to_h)).to_s.squish.presence || defaults[key]]
    end
    [values.compact, values.select { |_key, value| value.nil? }.keys]
  end

  def self.missing_reason(keys)
    "falta #{keys.map { |key| "{{#{key}}}" }.join(', ')}"
  end

  private

  def valid_shape?
    return false if keys.size > MAX_VARIABLES || defaults.values.any? { |text| text.size > MAX_TEXT_LENGTH }

    valid_keys? && bindings.values.all? { |bound| valid_binding?(bound) }
  end

  def valid_keys?
    keys.all? { |key| key.present? && key.size <= MAX_KEY_LENGTH }
  end

  def valid_binding?(bound)
    value = bound['value'].to_s
    case bound['source']
    when 'contact' then CONTACT_FIELDS.key?(value)
    when 'column' then value.present?
    when 'fixed' then value.strip.present? && value.size <= MAX_TEXT_LENGTH
    when 'field' then TemplateFields::Catalog.in_audience?(value)
    else false
    end
  end

  def coverage_mapping
    bindings.each_with_object({}) do |(key, bound), mapping|
      source = coverage_source(bound)
      mapping[key] = source if source
    end
  end

  # Only what the spreadsheet row holds is checked before sending; the other fields are read at send time.
  def coverage_source(bound)
    column = audience_column(bound)
    return { 'source' => 'extra', 'column' => column } if column

    field = catalog_key(bound)
    COVERAGE_FIELDS[field] && { 'source' => COVERAGE_FIELDS[field] }
  end

  def unknown_columns(campaign_import)
    bindings.values.filter_map { |bound| audience_column(bound) } - Array(campaign_import.extra_columns)
  end

  # The audience column a 'column' or 'field publico.<column>' binding reads.
  def audience_column(bound)
    return bound['value'] if bound['source'] == 'column'

    key = bound['value'].to_s
    TemplateFields::Catalog.audience_column(key) if bound['source'] == 'field' && TemplateFields::Catalog.audience_key?(key)
  end

  def catalog_key(bound)
    case bound['source']
    when 'contact' then CONTACT_FIELDS[bound['value']]
    when 'field' then bound['value']
    end
  end

  def value_for(bound, fields, extra_values)
    case bound['source']
    when 'fixed' then bound['value']
    when 'column' then extra_values[bound['value']]
    when 'contact', 'field' then fields.value(catalog_key(bound))
    end
  end

  def field_resolver(contact, extra_values)
    TemplateFields::Resolver.new(
      TemplateFields::ContactResolver.new(contact), account_resolver(contact.account),
      TemplateFields::AudienceResolver.new(columns: extra_values.keys, values: extra_values, types: @column_types)
    )
  end

  # One per account for the whole send: the brand kit is read once.
  def account_resolver(account)
    @account_resolvers ||= {}
    @account_resolvers[account.id] ||= TemplateFields::AccountResolver.new(account)
  end
end
