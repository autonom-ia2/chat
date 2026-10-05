# The text of a journey SMS campaign (#1004, PRD §6.3) and its per-person tokens. It reuses the
# WhatsApp API journey token pieces (#999, api-999.md §2.2.1), so the screen uses one grammar:
#
#   {{contact.name}}, {{contact.first_name}}, {{contact.company}} and {{publico.<key>}}
#
# - Supported tokens and rendering: WhatsappApiCampaigns::TemplateRenderer (one left-to-right
#   pass, no regular expressions; an inserted value is never read again as a token nor as Liquid).
# - Audience columns: CampaignJourney::AudienceColumns (<key> normalized like the importer; value
#   from the contact's first imported row).
# - Defaults are keyed by token ("contact.company", "publico.vencimento"), as in #999.
#
# A person without a company or a column value, and without the default of that token, is skipped
# with "falta empresa" / "falta vencimento, plano" (B1b). An empty name renders as empty text.
class CampaignJourney::SmsMessage
  class Error < StandardError
    attr_reader :details

    def initialize(code, details = nil)
      @details = details
      super(code)
    end
  end

  RENDERER = WhatsappApiCampaigns::TemplateRenderer
  COMPANY = RENDERER::COMPANY_VARIABLE
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
    @tokens ||= RENDERER.variables_in(@text)
  end

  # Checked when the campaign is created (same order and codes as the WhatsApp API journey).
  def validate!
    raise Error, 'message_too_long' if @text.size > MAX_LENGTH

    unknown_columns = tokens.filter_map { |token| CampaignJourney::AudienceColumns.column_key(token) } - column_keys
    raise Error.new('unknown_audience_column', unknown: unknown_columns) if unknown_columns.any?

    unsupported = RENDERER.unsupported_variables_in(@text, audience_keys: column_keys)
    raise Error.new('unsupported_variables', unknown: unsupported) if unsupported.any?

    validate_defaults!
  end

  # => ['Olá Ana, vence 10/2026', []] or [nil, ['empresa', 'vencimento']] when values are missing.
  def render_for(contact)
    values = per_person_values(contact).to_h { |token, value| [token, value.presence || defaults[token]] }
    missing = values.select { |_token, value| value.nil? }.keys
    return [nil, missing.map { |token| missing_name(token) }] if missing.any?

    [RENDERER.new(template: @text, contact: contact, variables: values).render, []]
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

  def column_keys
    @column_keys ||= CampaignJourney::AudienceColumns.key_map(@campaign_import).keys
  end

  # { 'publico.vencimento' => '10/2026' or nil, 'contact.company' => 'Alfa' or nil } for the
  # tokens that may be missing, in the message order; name tokens always render.
  def per_person_values(contact)
    row = nil
    tokens.each_with_object({}) do |token, values|
      key = CampaignJourney::AudienceColumns.column_key(token)
      if key
        row ||= CampaignJourney::AudienceColumns.row_values(@campaign_import, contact.id)
        values[token] = row[key]
      elsif token == COMPANY
        values[token] = RENDERER.company_name(contact)
      end
    end
  end

  def missing_name(token)
    token == COMPANY ? 'empresa' : CampaignJourney::AudienceColumns.column_key(token)
  end
end
