# Message variables of a journey campaign (#1005, PRD §6.3 and B1b). Each template variable is
# bound to a contact field, an audience column (campaign_import_rows.extra_values) or a fixed
# text, and/or has a default used when the person has no value:
#
#   bindings: { '1' => { 'source' => 'contact', 'value' => 'first_name' },
#               '2' => { 'source' => 'column',  'value' => 'Vencimento' },
#               '3' => { 'source' => 'fixed',   'value' => 'Equipe Hub2You' } }
#   defaults: { '2' => 'em breve' }   # a default alone works as a fixed text
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

  SOURCES = %w[contact column fixed].freeze
  CONTACT_FIELDS = %w[name first_name company].freeze
  MAX_VARIABLES = 20
  MAX_KEY_LENGTH = 50
  MAX_TEXT_LENGTH = 1024

  attr_reader :bindings, :defaults

  def initialize(bindings, defaults = {})
    @bindings = bindings.to_h.to_h { |key, bound| [key.to_s, bound.to_h.stringify_keys.slice('source', 'value')] }
    @defaults = defaults.to_h.to_h { |key, text| [key.to_s, text.to_s.squish] }.compact_blank
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
    values = keys.to_h do |key|
      bound = bindings[key]
      [key, (bound && value_for(bound, contact, extra_values.to_h)).to_s.squish.presence || defaults[key]]
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
    when 'contact' then CONTACT_FIELDS.include?(value)
    when 'column' then value.present?
    when 'fixed' then value.strip.present? && value.size <= MAX_TEXT_LENGTH
    else false
    end
  end

  def coverage_mapping
    bindings.each_with_object({}) do |(key, bound), mapping|
      case bound['source']
      when 'column' then mapping[key] = { 'source' => 'extra', 'column' => bound['value'] }
      when 'contact' then mapping[key] = { 'source' => bound['value'] == 'company' ? 'company' : 'name' }
      end
    end
  end

  def unknown_columns(campaign_import)
    columns = bindings.values.select { |bound| bound['source'] == 'column' }.pluck('value')
    columns - Array(campaign_import.extra_columns)
  end

  def value_for(bound, contact, extra_values)
    case bound['source']
    when 'fixed' then bound['value']
    when 'column' then extra_values[bound['value']]
    when 'contact' then contact_field(contact, bound['value'])
    end
  end

  def contact_field(contact, field)
    case field
    when 'name' then contact.name
    when 'first_name' then contact.name.to_s.split.first
    when 'company' then contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name']
    end
  end
end
