# What a saved audience keeps of each person besides name, phone, e-mail and company (#2277): the city and country of
# the contact and every contact custom attribute of the account, as the extra columns a spreadsheet audience leaves
# (campaign_imports.extra_columns + campaign_import_rows.extra_values, CampaignJourney::AudienceColumns). A campaign
# message then uses them as publico.<coluna> ("João, de Belo Horizonte, que torce para o Cruzeiro").
#
# A column nobody of the audience has a value for is left out. Dates, money and links get the type the message formats
# them by (CampaignImports::ColumnTypes). A column whose key is taken (another column, or a key the campaign fills
# by itself: nome, primeiro_nome, empresa, email...) gets " (2)": an attribute "Empresa" never replaces the company.
class ConversationAudience::Columns
  Column = Struct.new(:header, :type, :read)

  STANDARD = %w[city country].freeze
  # Keys the campaign message already fills (CampaignJourney::EmailAudienceRecipients#custom_data and its RESERVED_KEYS).
  TAKEN = %w[nome primeiro_nome empresa email contact unsubscribe_url].freeze
  TYPES = { 'date' => 'data', 'currency' => 'moeda', 'link' => 'link' }.freeze

  def initialize(account, contacts)
    @account = account
    @contacts = contacts
  end

  # ['Cidade', 'Time do coração', ...] in the order of the account's fields.
  def headers
    used.map(&:header)
  end

  # { 'Cidade' => 'Belo Horizonte', 'Time do coração' => 'Cruzeiro' } of one contact (blanks left out).
  def values_for(contact)
    used.to_h { |column| [column.header, text(column.read.call(contact), column.type)] }.compact_blank
  end

  # { 'Aniversário' => 'data' } for the columns with a type.
  def types
    used.to_h { |column| [column.header, column.type] }.compact
  end

  private

  def used
    @used ||= all.select { |column| @contacts.any? { |contact| text(column.read.call(contact), column.type).present? } }
  end

  def all
    taken = TAKEN.dup
    (standard + custom).map do |column|
      header = free_header(column.header, taken)
      taken << key(header)
      Column.new(header, column.type, column.read)
    end
  end

  def free_header(header, taken)
    count = 1
    candidate = header
    candidate = "#{header} (#{count += 1})" while taken.include?(key(candidate))
    candidate
  end

  def key(header)
    CampaignImports::HeaderMapper.normalize_key(header)
  end

  def standard
    STANDARD.map do |key|
      Column.new(I18n.t("conversation_audience.columns.#{key}", locale: locale), nil, ->(contact) { contact.additional_attributes.to_h[key] })
    end
  end

  def custom
    @account.custom_attribute_definitions.contact_attribute.order(:id).map do |definition|
      key = definition.attribute_key
      Column.new(definition.attribute_display_name.to_s.squish, TYPES[definition.attribute_display_type],
                 ->(contact) { contact.custom_attributes.to_h[key] })
    end
  end

  def text(value, type)
    case value
    when true, false then I18n.t("conversation_audience.columns.#{value ? 'yes' : 'no'}", locale: locale)
    when Array then value.compact_blank.join(', ')
    else type == 'data' ? iso_date(value) : value.to_s.squish
    end
  end

  # A date attribute is saved as "2026-10-14" or a full timestamp; the column keeps the day, as a spreadsheet date.
  def iso_date(value)
    Date.iso8601(value.to_s.first(10)).iso8601
  rescue Date::Error
    value.to_s.squish
  end

  def locale
    @locale ||= I18n.available_locales.map(&:to_s).include?(@account.locale.to_s) ? @account.locale : I18n.default_locale
  end
end
