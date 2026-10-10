# Closed tables from the merge tags of other e-mail platforms to ours (#1099). Each syntax family has its own reading;
# the names below are the ones those platforms document for name, first name, e-mail, company and job title, their
# unsubscribe link, their platform-only links (view in browser, preferences) and their noise (year, list address,
# badges). Anything else is an unknown field: kept as {{ key }} and listed, never guessed. No regex.
module EmailCampaigns::Import::MergeTags::Catalog
  Resolution = Struct.new(:kind, :key, :simplified, keyword_init: true)

  FIELDS = {
    'nome' => %w[nome name full_name fullname lead.nome lead.name contact.name contact.nome contact.full_name person.full_name
                 subscriber.name],
    'primeiro_nome' => %w[primeiro_nome first_name firstname fname lead.primeiro_nome lead.first_name contact.firstname
                          contact.first_name contact.primeiro_nome person.first_name subscriber.first_name],
    'email' => %w[email e-mail lead.email contact.email person.email subscriber.email email_to],
    'empresa' => %w[empresa company company_name lead.empresa lead.company contact.company contact.empresa contact.company_name
                    person.organization],
    'cargo' => %w[cargo jobtitle job_title lead.cargo lead.job_title contact.jobtitle contact.job_title contact.cargo person.title]
  }.flat_map { |key, names| names.map { |name| [name, key] } }.to_h.freeze
  # Fields the contact list must carry (custom_data columns), on top of TemplateValidator::DEFAULT_KEYS.
  LIST_FIELDS = %w[primeiro_nome empresa cargo].freeze
  OUR_FIELDS = (FIELDS.values.uniq + ['unsubscribe_url']).freeze
  UNSUBSCRIBE = %w[unsubscribe unsubscribe_url unsubscribe_link unsubscribe_link_all unsub unsub_link].freeze
  UNSUBSCRIBE_PREFIXES = %w[unsub_link_ unsubscribe_link_].freeze
  PLATFORM_LINKS = %w[archive archive_page mirror permalink view_as_page_url web_view webversion view_in_browser update_profile
                      preferences manage_preferences forward].freeze
  NOISE = %w[subject current_year uniqid mc_preview_text rewards rewards_text list_address].freeze
  NOISE_PREFIXES = %w[site_settings. organization. list: html: mc: date: account.].freeze
  OPEN = %w[if unless for each with ifnot].freeze
  ELSE = %w[else elsif elif elseif].freeze
  CLOSE = %w[endif endunless endfor endeach endwith].freeze
  KEY_CHARS = (('a'..'z').to_a + ('0'..'9').to_a + ['_']).freeze
  # The last name of the star-pipe family; right after the first name it makes the full name.
  FIRST_NAME = 'fname'.freeze
  LAST_NAME = 'lname'.freeze

  module_function

  def resolve(token)
    inner = token.inner.strip.delete_prefix('-').delete_suffix('-').strip
    case token.syntax
    when :statement then statement(inner)
    when :star_pipe then star_pipe(inner)
    else expression(inner)
    end
  end

  def statement(inner)
    head = inner.split.first.to_s.downcase
    return flow(head) if flow(head)
    return Resolution.new(kind: :unsubscribe) if UNSUBSCRIBE.include?(head)
    return Resolution.new(kind: :platform_link) if PLATFORM_LINKS.include?(head)

    Resolution.new(kind: :statement)
  end

  def flow(head)
    return Resolution.new(kind: :open) if OPEN.include?(head)
    return Resolution.new(kind: :else) if ELSE.include?(head)

    Resolution.new(kind: :close) if CLOSE.include?(head)
  end

  def star_pipe(inner)
    upper = inner.upcase
    return Resolution.new(kind: :open) if upper.start_with?('IF:', 'IFNOT:')
    return Resolution.new(kind: :else) if upper.start_with?('ELSEIF:') || upper == 'ELSE:'
    return Resolution.new(kind: :close) if upper == 'END:IF'

    named(inner.downcase)
  end

  def expression(inner)
    section = section_marker(inner)
    return section if section

    name = inner.split('|').first.to_s.strip
    simplified = inner.include?('|')
    name, argument = function_argument(name) if name.include?('(')
    name, default = colon_name(name) if name.include?(':')
    resolution = named(name.downcase)
    resolution.simplified = simplified || argument || default
    resolution
  end

  # Mustache sections ({{#each}}, {{^x}}, {{/each}}) and {{else}} work as conditionals.
  def section_marker(inner)
    return Resolution.new(kind: :open) if inner.start_with?('#', '^')
    return Resolution.new(kind: :close) if inner.start_with?('/')

    Resolution.new(kind: :else) if inner.downcase == 'else'
  end

  # personalization_token('contact.firstname', 'tudo bem') -> ['contact.firstname', true]
  def function_argument(name)
    arguments = name.split('(', 2).last.to_s.lstrip
    quote = arguments[0]
    return [name, false] unless ['"', "'"].include?(quote)

    [arguments[1..].split(quote).first.to_s, arguments.include?(',')]
  end

  # data:firstname:"cliente" / var:empresa:"a sua empresa" -> ['firstname', true]
  def colon_name(name)
    parts = name.split(':')
    return [name, false] unless %w[data var].include?(parts.first.downcase) && parts.size > 1

    [parts[1], parts.size > 2]
  end

  def named(lower)
    return Resolution.new(kind: :field, key: FIELDS[lower]) if FIELDS.key?(lower)
    return Resolution.new(kind: :unsubscribe) if unsubscribe?(lower)
    return Resolution.new(kind: :platform_link) if PLATFORM_LINKS.include?(lower)
    return Resolution.new(kind: :noise) if NOISE.include?(lower) || NOISE_PREFIXES.any? { |prefix| lower.start_with?(prefix) }

    Resolution.new(kind: :unknown, key: key_for(lower))
  end

  def unsubscribe?(lower)
    UNSUBSCRIBE.include?(lower) || UNSUBSCRIBE_PREFIXES.any? { |prefix| lower.start_with?(prefix) }
  end

  # The last segment of the name, or all of it when the last segment alone would read as one of our fields.
  def key_for(lower)
    segment = lower.split('.').last.to_s.split(':').last.to_s
    segment = lower if OUR_FIELDS.include?(slug(segment))
    key = slug(segment)
    key.empty? ? 'campo' : key
  end

  def slug(text)
    text.each_char.map { |char| KEY_CHARS.include?(char) ? char : '_' }.join.squeeze('_').delete_prefix('_').delete_suffix('_')
  end
end
