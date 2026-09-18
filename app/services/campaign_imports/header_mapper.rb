module CampaignImports
  class HeaderMapper
    ALIASES = {
      name: ['nome', 'name', 'cliente', 'contato', 'nome completo', 'paciente'],
      phone_number: ['telefone', 'phone', 'phone_number', 'whatsapp', 'celular', 'numero', 'número'],
      email: ['email', 'e-mail', 'e mail', 'correio', 'correio eletronico', 'correio eletrônico']
    }.freeze
    EMAIL_CONTAINS_ALIASES = ['email', 'e-mail', 'e mail'].freeze

    Result = Struct.new(:mapping, :errors, :extra_columns, keyword_init: true)

    def initialize(headers, mode: :phone)
      @headers = Array(headers)
      @mode = mode
    end

    def perform
      mapping = {}
      duplicated = []

      normalized_headers.each_with_index do |header, index|
        logical_name = logical_name_for(header)
        next if logical_name.nil?

        duplicated << logical_name if mapping.key?(logical_name)
        mapping[logical_name] ||= index
      end

      errors = []
      errors << 'missing_name_header' unless mapping.key?(:name)
      if @mode == :email
        errors << 'missing_email_header' unless mapping.key?(:email)
      else
        errors << 'missing_phone_number_header' unless mapping.key?(:phone_number)
      end
      errors += duplicated.uniq.map { |column| "duplicated_#{column}_header" }

      Result.new(mapping: mapping, errors: errors, extra_columns: extra_columns(mapping))
    end

    def self.normalize(header)
      transliterate(header.to_s)
        .downcase
        .strip
        .tr('_-', ' ')
        .gsub(/\s+/, ' ')
    end

    def self.transliterate(value)
      return I18n.transliterate(value) if defined?(I18n)

      value.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '')
    end

    # Normalized custom-data key: trim, NFKD without accents, downcase,
    # spaces/dashes -> underscore, strip anything outside [a-z0-9_].
    def self.normalize_key(header)
      transliterate(header.to_s.strip)
        .downcase
        .gsub(/[\s-]+/, '_')
        .gsub(/[^a-z0-9_]/, '')
    end

    private

    def normalized_headers
      @normalized_headers ||= @headers.map { |header| self.class.normalize(header) }
    end

    # Email mode keeps every unmapped column as a normalized custom-data key.
    # Post-normalization collisions get a `_2` suffix.
    def extra_columns(mapping)
      return {} unless @mode == :email

      taken = mapping.values
      columns = {}
      @headers.each_with_index do |header, index|
        next if taken.include?(index)

        key = self.class.normalize_key(header)
        next if key.empty?

        key = "#{key}_2" while columns.key?(key)
        columns[key] = index
      end
      columns
    end

    # In :email mode only name/email are logical columns; phone-like headers
    # (telefone/celular/whatsapp/numero/...) fall through to extra_columns and
    # never trigger a duplicated_phone_number_header error.
    def logical_name_for(header)
      candidates = @mode == :email ? ALIASES.slice(:name, :email) : ALIASES
      candidates.each do |logical_name, aliases|
        return logical_name if email_header_contains_alias?(logical_name, header)
        return logical_name if aliases.map { |item| self.class.normalize(item) }.include?(header)
      end

      nil
    end

    def email_header_contains_alias?(logical_name, header)
      return false unless @mode == :email && logical_name == :email

      EMAIL_CONTAINS_ALIASES
        .map { |item| self.class.normalize(item) }
        .any? { |item| header.include?(item) }
    end
  end
end
