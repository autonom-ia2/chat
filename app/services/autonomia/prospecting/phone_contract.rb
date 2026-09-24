# Contrato único de telefone da prospecção (#677): um número vira E.164 pela gem
# telephone_number, com a região (ISO 3166 alfa-2) vinda de settings.metadata['search_country'].
# O front repete a mesma regra em utils/phoneContract.js; os dois rodam a tabela
# spec/fixtures/prospecting_phone_contract_cases.json.
#
# Regra: número com + é lido como internacional. Sem +, primeiro como número
# nacional da região (assim "(55) 99988-7766" é DDD 55, não o DDI do Brasil);
# se não for válido lá, como internacional sem o +. Número que não valida em
# nenhum dos dois não tem telefone.
module Autonomia::Prospecting::PhoneContract
  DEFAULT_REGION = 'BR'.freeze
  CHAT_ID_SUFFIX = '@c.us'.freeze

  Phone = Struct.new(:e164, :digits, :country_iso2, keyword_init: true)

  module_function

  def parse(raw, region: DEFAULT_REGION)
    text = raw.to_s.strip
    return if text.empty?

    candidates(text, normalize_region(region)).each do |candidate, country|
      parsed = country ? TelephoneNumber.parse(candidate, country) : TelephoneNumber.parse(candidate)
      next unless parsed.valid?

      e164 = parsed.e164_number
      return Phone.new(e164: e164, digits: e164.delete('+'), country_iso2: parsed.country&.country_id)
    end
    nil
  end

  def e164(raw, region: DEFAULT_REGION)
    parse(raw, region: region)&.e164
  end

  def chat_id(raw, region: DEFAULT_REGION)
    digits = parse(raw, region: region)&.digits
    digits && "#{digits}#{CHAT_ID_SUFFIX}"
  end

  def region_for(account)
    setting = Autonomia::Prospecting::Setting.find_by(account: account)
    normalize_region(setting&.search_country)
  end

  def normalize_region(region)
    code = region.to_s.strip.upcase
    TelephoneNumber::Country.find(code.downcase.to_sym) ? code : DEFAULT_REGION
  end

  def candidates(text, region)
    return [[text, nil]] if text.start_with?('+')

    digits = text.delete('^0-9')
    return [] if digits.empty?

    [[text, region.downcase.to_sym], ["+#{digits}", nil]]
  end
  private_class_method :candidates
end
