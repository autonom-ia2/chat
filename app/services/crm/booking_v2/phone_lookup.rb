# Telefone de quem agenda pelo link (#1188): valida e normaliza para E.164 com a biblioteca de telefone do sistema
# (`TelephoneNumber`) e acha o contato existente da conta, inclusive gravado sem o nono dígito brasileiro.
#
# Variantes do nono dígito: reaproveita `Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer#contact_candidates`, que
# trabalha só com dígitos e não precisa de caixa (a caixa só entra em `PhoneNumberNormalizationService` para achar o
# `ContactInbox`). Outros países: só a forma exata.
#
# Nunca altera o contato achado (o nome digitado na página não sobrescreve o que o atendimento já tem).
class Crm::BookingV2::PhoneLookup
  DEFAULT_REGION = :br
  MAX_INPUT_LENGTH = 40
  BRAZIL_PREFIX = '55'.freeze

  class << self
    # `raw` pode vir com ou sem `+`. Sem `+`, o número é lido como do país `region` (ex.: "11 91234-5678" no Brasil).
    # Devolve "+5511912345678" ou nil quando o número não é válido.
    def normalize(raw, region: DEFAULT_REGION)
      value = raw.to_s.strip
      return if value.blank? || value.length > MAX_INPUT_LENGTH

      parsed = value.start_with?('+') ? TelephoneNumber.parse(value) : TelephoneNumber.parse(value, region.to_s.downcase.to_sym)
      return unless parsed.valid?

      parsed.e164_number.presence
    end

    # País padrão a partir do fuso do perfil (America/Sao_Paulo -> :br). Sem correspondência, Brasil.
    def region_for(timezone)
      identifier = ActiveSupport::TimeZone[timezone.to_s]&.tzinfo&.identifier || timezone.to_s
      zone_countries.fetch(identifier, DEFAULT_REGION)
    end

    def find_contact(account:, e164:)
      return if account.blank? || e164.blank?

      options = candidates(e164)
      found = account.contacts.where(phone_number: options).to_a
      options.lazy.filter_map { |number| found.find { |contact| contact.phone_number == number } }.first
    end

    # Formas equivalentes do mesmo número, a exata primeiro.
    def candidates(e164)
      digits = e164.to_s.delete_prefix('+')
      return [e164] unless digits.start_with?(BRAZIL_PREFIX)

      Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.contact_candidates(digits).map { |number| "+#{number}" }
    end

    private

    def zone_countries
      @zone_countries ||= TZInfo::Country.all.each_with_object({}) do |country, map|
        country.zone_identifiers.each { |zone| map[zone] ||= country.code.downcase.to_sym }
      end.freeze
    end
  end
end
