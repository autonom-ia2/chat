require 'digest'

module CampaignImports
  class PhoneNormalizer
    Error = Class.new(StandardError)
    Result = Struct.new(:phone_number, :hash, :masked, keyword_init: true)

    class << self
      def normalize!(raw_phone)
        sanitized = raw_phone.to_s.strip.delete_prefix("'")
        raise Error, 'blank_phone_number' if sanitized.empty?
        raise Error, 'formula_phone_number' if CsvSanitizer.formula_like?(sanitized, allow_phone_plus: true)

        digits = sanitized.gsub(/\D/, '')
        local_number = local_mobile_number(digits)
        raise Error, 'invalid_brazilian_mobile_number' if local_number.nil? || local_number.empty?

        normalized = "+55#{local_number}"
        Result.new(
          phone_number: normalized,
          hash: Digest::SHA256.hexdigest(normalized),
          masked: mask(normalized)
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

      # Ways a spreadsheet writes the same mobile: the long-distance trunk 0 ("011 98765-4321", or
      # "0055…" for the international prefix) and the legacy eight-digit mobile from before the ninth
      # digit, restored by the WhatsApp normalizer (Anatel: only 6-9 ranges, never a landline).
      def national_digits(digits)
        digits = digits[1..] while digits.start_with?('0')
        digits = "55#{digits}" if digits.length == 10
        return digits unless digits.length == 12 && digits.start_with?('55')

        Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(digits)
      end

      def local_mobile_number(digits)
        digits = national_digits(digits)
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
    end
  end
end
