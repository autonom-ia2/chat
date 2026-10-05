# The text of a journey SMS campaign (#1004, PRD §6.3) and its per-person tokens. Same grammar as
# the WhatsApp API journey message (#999, api-999.md §2.2.1), so the screen uses one grammar:
#
#   {{contact.name}}, {{contact.first_name}}, {{contact.company}} and {{publico.<key>}}
#
# <key> is an extra column of the audience normalized like the importer
# (CampaignImports::HeaderMapper.normalize_key: "Data de Vencimento" → "data_de_vencimento"; a
# repeated key gets "_2"); the value is campaign_import_rows.extra_values of the contact's first
# imported row. Defaults are keyed by token ("contact.company", "publico.vencimento").
#
# A person without a company or a column value, and without the default of that token, is skipped
# with "falta empresa" / "falta vencimento, plano" (B1b). An empty name renders as empty text.
# Read and filled in one left-to-right pass (CampaignJourney::TemplatePlaceholders, no regular
# expressions): an inserted value is never read again as a token, nor as Liquid.
class CampaignJourney::SmsMessage
  class Error < StandardError
    attr_reader :details

    def initialize(code, details = nil)
      @details = details
      super(code)
    end
  end

  COMPANY = 'contact.company'.freeze
  CONTACT_TOKENS = ['contact.name', 'contact.first_name', COMPANY].freeze
  COLUMN_PREFIX = 'publico.'.freeze
  # Twilio refuses a body over 1600 characters.
  MAX_LENGTH = 1600
  MAX_DEFAULT_LENGTH = 1024

  attr_reader :text, :defaults

  def initialize(text, campaign_import:, defaults: {})
    @text = text.to_s
    @campaign_import = campaign_import
    @raw_defaults = defaults.to_h.transform_keys(&:to_s)
    @defaults = @raw_defaults.transform_values { |value| value.to_s.squish }.compact_blank
  end

  def tokens
    @tokens ||= CampaignJourney::TemplatePlaceholders.keys(@text)
  end

  # Checked when the campaign is created.
  def validate!
    raise Error, 'message_too_long' if @text.size > MAX_LENGTH

    unsupported = tokens.reject { |token| CONTACT_TOKENS.include?(token) || column_key(token) }
    raise Error.new('unsupported_variables', unknown: unsupported) if unsupported.any?

    unknown_columns = tokens.filter_map { |token| column_key(token) } - column_headers.keys
    raise Error.new('unknown_audience_column', unknown: unknown_columns) if unknown_columns.any?

    validate_defaults!
  end

  # => ['Olá Ana, vence 10/2026', []] or [nil, ['empresa', 'vencimento']] when values are missing.
  def render_for(contact)
    extra_values = tokens.any? { |token| column_key(token) } ? first_row_values(contact.id) : {}
    values = tokens.index_with { |token| value_for(token, contact, extra_values) }
    missing = values.select { |_token, value| value.nil? }.keys
    return [nil, missing.map { |token| missing_name(token) }] if missing.any?

    [CampaignJourney::TemplatePlaceholders.render(@text, values), []]
  end

  def self.missing_reason(names)
    "falta #{names.join(', ')}"
  end

  private

  def validate_defaults!
    unknown = @raw_defaults.keys - tokens
    too_long = @raw_defaults.values.any? { |value| value.to_s.size > MAX_DEFAULT_LENGTH }
    raise Error.new('invalid_variable_defaults', unknown: unknown) if unknown.any? || too_long
  end

  def column_key(token)
    token.start_with?(COLUMN_PREFIX) ? token.delete_prefix(COLUMN_PREFIX).presence : nil
  end

  # { 'vencimento' => 'Vencimento', 'data_de_vencimento' => 'Data de Vencimento' }
  def column_headers
    @column_headers ||= Array(@campaign_import&.extra_columns).each_with_object({}) do |header, map|
      key = CampaignImports::HeaderMapper.normalize_key(header)
      next if key.empty?

      key = "#{key}_2" while map.key?(key)
      map[key] = header.to_s
    end
  end

  def value_for(token, contact, extra_values)
    case token
    when 'contact.name' then contact.name.to_s.squish
    when 'contact.first_name' then contact.name.to_s.split.first.to_s
    when COMPANY then company_name(contact) || defaults[token]
    else extra_values[column_headers[column_key(token)]].to_s.squish.presence || defaults[token]
    end
  end

  # Same source as the WhatsApp journey variables (CampaignJourney::VariableBindings).
  def company_name(contact)
    (contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name']).to_s.squish.presence
  end

  # extra_values of the contact's first imported row in the audience.
  def first_row_values(contact_id)
    return {} if @campaign_import.nil?

    @campaign_import.campaign_import_rows.status_imported.where(contact_id: contact_id).order(:row_number).pick(:extra_values).to_h
  end

  def missing_name(token)
    token == COMPANY ? 'empresa' : column_key(token)
  end
end
