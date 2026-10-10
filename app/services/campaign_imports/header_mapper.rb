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

    def perform(explicit_mapping: nil)
      return explicit_result(explicit_mapping) if explicit_mapping

      mapping = {}
      duplicated = []

      normalized_headers.each_with_index do |header, index|
        logical_name = logical_name_for(header)
        next if logical_name.nil?

        duplicated << logical_name if mapping.key?(logical_name)
        mapping[logical_name] ||= index
      end

      errors = required_errors(mapping)
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

    def self.normalize_key(header)
      transliterate(header.to_s.strip)
        .downcase
        .gsub(/[\s-]+/, '_')
        .gsub(/[^a-z0-9_]/, '')
    end

    private

    def explicit_result(mapping)
      normalized = mapping.to_h.symbolize_keys.compact
      valid_indices = normalized.values.all? { |index| index.is_a?(Integer) && index.between?(0, @headers.length - 1) }
      unique_indices = normalized.values.uniq.length == normalized.values.length
      return Result.new(mapping: normalized, errors: ['invalid_header_mapping'], extra_columns: {}) unless valid_indices && unique_indices

      Result.new(mapping: normalized, errors: required_errors(normalized), extra_columns: extra_columns(normalized))
    end

    def required_errors(mapping)
      errors = []
      errors << 'missing_name_header' if @mode != :email && !mapping.key?(:name)
      if @mode == :email
        errors << 'missing_email_header' unless mapping.key?(:email)
      else
        errors << 'missing_phone_number_header' unless mapping.key?(:phone_number)
      end
      errors
    end

    def normalized_headers
      @normalized_headers ||= @headers.map { |header| self.class.normalize(header) }
    end

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
      return false if header.include?('@')

      EMAIL_CONTAINS_ALIASES
        .map { |item| self.class.normalize(item) }
        .any? { |item| header.include?(item) }
    end
  end
end
