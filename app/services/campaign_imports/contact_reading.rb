# How the contact cells of a spreadsheet are read (#1246). CLASSIC is the reading every account has.
# CUSTOMER_BASE (account flag customer_base, Base de clientes #1240) also accepts the national ways of
# writing a mobile (trunk 0, legacy number without the ninth digit, see PhoneNormalizer), cells with
# several values (CellValues) and files without a header (HeaderLocator), and gives Jev the share of
# valid values in each column (TypesafeAi::AudienceSchemaResolver).
class CampaignImports::ContactReading
  FLAG = 'customer_base'.freeze

  def self.for(account)
    account&.feature_enabled?(FLAG) ? CUSTOMER_BASE : CLASSIC
  end

  def initialize(customer_base:)
    @customer_base = customer_base
    freeze
  end

  def customer_base?
    @customer_base
  end

  # -> CampaignImports::PhoneNormalizer::Result, or raises PhoneNormalizer::Error
  def phone(value)
    return CampaignImports::PhoneNormalizer.normalize!(value) unless customer_base?

    CampaignImports::CellValues.first_valid(value, CampaignImports::PhoneNormalizer::Error) do |part|
      CampaignImports::PhoneNormalizer.normalize!(part, national_formats: true)
    end
  end

  # -> EmailCampaigns::EmailNormalizer result, or raises EmailNormalizer::Error
  def email(value)
    return EmailCampaigns::EmailNormalizer.normalize!(value) unless customer_base?

    CampaignImports::CellValues.first_valid(value, EmailCampaigns::EmailNormalizer::Error) do |part|
      EmailCampaigns::EmailNormalizer.normalize!(part)
    end
  end

  def phone?(value)
    customer_base? ? valid?(value) { |text| phone(text) } : CampaignImports::ContactValues.phone?(value)
  end

  def email?(value)
    customer_base? ? valid?(value) { |text| email(text) } : CampaignImports::ContactValues.email?(value)
  end

  def contact?(value)
    phone?(value) || email?(value)
  end

  private

  def valid?(value)
    text = value.to_s.strip
    return false if text.empty? || !CampaignImports::ContactValues.readable?(text)

    yield(text)
    true
  rescue CampaignImports::PhoneNormalizer::Error, EmailCampaigns::EmailNormalizer::Error
    false
  end

  CLASSIC = new(customer_base: false)
  CUSTOMER_BASE = new(customer_base: true)
end
