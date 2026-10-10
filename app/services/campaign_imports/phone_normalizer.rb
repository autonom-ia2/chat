require 'digest'

module CampaignImports
  class PhoneNormalizer
    Error = Class.new(StandardError)
    Result = Struct.new(:phone_number, :hash, :masked, :ninth_digit_added, keyword_init: true)
    # Anatel's area codes. A number outside them is not a Brazilian mobile, whatever its length.
    DDDS = %w[11 12 13 14 15 16 17 18 19 21 22 24 27 28 31 32 33 34 35 37 38 41 42 43 44 45 46 47 48 49 51 53 54 55
              61 62 63 64 65 66 67 68 69 71 73 74 75 77 79 81 82 83 84 85 86 87 88 89 91 92 93 94 95 96 97 98 99].freeze
    LEGACY_NATIONAL_LENGTH = 10

    class << self
      # national_formats (customer_base reading, #1246): also the other ways a Brazilian sheet writes a
      # mobile. See #national_mobile_number.
      def normalize!(raw_phone, national_formats: false)
        sanitized = raw_phone.to_s.strip.delete_prefix("'")
        raise Error, 'blank_phone_number' if sanitized.empty?
        raise Error, 'formula_phone_number' if CsvSanitizer.formula_like?(sanitized, allow_phone_plus: true)

        digits = sanitized.gsub(/\D/, '')
        local_number, ninth_digit_added = national_formats ? national_mobile_number(sanitized, digits) : [local_mobile_number(digits), false]
        raise Error, 'invalid_brazilian_mobile_number' if local_number.nil? || local_number.empty?

        normalized = "+55#{local_number}"
        Result.new(
          phone_number: normalized,
          hash: Digest::SHA256.hexdigest(normalized),
          masked: mask(normalized),
          ninth_digit_added: ninth_digit_added
        )
      end

      # Country code and last 4 digits only (CampaignImports::PhoneMask, #993).
      def mask(phone_number)
        CampaignImports::PhoneMask.mask(phone_number)
      end

      def mask_raw(raw_phone)
        CampaignImports::PhoneMask.mask(raw_phone)
      end

      private

      def local_mobile_number(digits)
        case digits.length
        when 11
          digits
        when 13
          return unless digits.start_with?('55')

          digits[2..]
        else
          nil
        end.then do |local|
          return nil if local.nil? || local.empty?

          ddd = local[0, 2]
          number = local[2..]
          next nil unless ddd.match?(/\A[1-9]{2}\z/)
          next nil unless number.match?(/\A9\d{8}\z/)

          local
        end
      end

      # -> [local number, ninth digit added?] or nil.
      # - wherever it is, "+" must be followed by 55, and then the DDD: "+1 917…", "Tel: +34 912…" and
      #   "+91 7555-1234" are other countries, "+55 8765-4321" has no DDD;
      # - leading zeros are the trunk or the international prefix ("011 98765-4321", "0055 11…");
      # - a legacy eight-digit mobile ("(11) 8765-4321") gets the ninth digit (Anatel: 6-9 ranges only,
      #   via the WhatsApp normalizer) when it is written the Brazilian way: the DDD apart, never in
      #   another country's grouping such as "917 555 1234";
      # - the DDD must be one of Anatel's.
      def national_mobile_number(written, digits)
        digits = written.include?('+') ? after_country_code(written) : national_digits(digits)
        return if digits.nil? || DDDS.exclude?(digits[0, 2])

        return [local_mobile_number(digits), false] unless digits.length == LEGACY_NATIONAL_LENGTH
        return unless brazilian_grouping?(written)

        [local_mobile_number(Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize("55#{digits}")), true]
      end

      # The digits after "+55", or nil when "+" brings another country.
      def after_country_code(written)
        international = written[written.index('+')..].delete('^0-9')
        international.delete_prefix('55') if international.start_with?('55')
      end

      def national_digits(digits)
        digits = without_leading_zeros(digits)
        digits.length > 11 && digits.start_with?('55') ? digits[2..] : digits
      end

      # Written without separators ("1187654321") it is the national format; with them, the DDD is a
      # group of its own once the trunk 0 and the country code are set aside.
      def brazilian_grouping?(written)
        groups = digit_groups(written)
        return true if groups.one?

        national = national_groups(groups)
        national.first.length == 2 && national.sum(&:length) == LEGACY_NATIONAL_LENGTH
      end

      def digit_groups(written)
        written.each_char.chunk_while { |left, right| digit?(left) == digit?(right) }.map(&:join).select { |group| digit?(group[0]) }
      end

      # "0xx11", "+55 11", "0055 11", "5511": the groups before the DDD are dropped. "(55) 8765-4321"
      # keeps its 55, the DDD of Rio Grande do Sul, because nothing else is left to be the DDD.
      def national_groups(groups)
        first, *rest = groups
        first = without_leading_zeros(first)
        return national_groups(rest) if prefix_group?(first, rest)
        return [first[2..], *rest] if glued_country_code?(first, groups)

        [first, *rest]
      end

      # A group made only of the trunk 0, or the country code with a whole national number after it.
      def prefix_group?(first, rest)
        rest.any? && (first.empty? || (first == '55' && rest.sum(&:length) >= LEGACY_NATIONAL_LENGTH))
      end

      # "5511 8765-4321": the country code written together with the DDD.
      def glued_country_code?(first, groups)
        first.length == 4 && first.start_with?('55') && groups.sum(&:length) > LEGACY_NATIONAL_LENGTH
      end

      def without_leading_zeros(text)
        text = text[1..] while text.start_with?('0')
        text
      end

      def digit?(char)
        char.between?('0', '9')
      end
    end
  end
end
