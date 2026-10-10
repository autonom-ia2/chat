# Dados do formulário de reserva da página nova (#1188), já limpos e conferidos contra a página: nome em texto puro,
# telefone em E.164, e-mail válido (ou nenhum), início ISO8601, duração e local oferecidos pela página.
#
# `validate!` levanta ArgumentError com o código do primeiro problema: invalid_name, invalid_phone, invalid_email,
# invalid_starts_at, invalid_duration, invalid_location. Separado do `Crm::BookingV2::Booker`, que cuida da reserva.
class Crm::BookingV2::BookingInput
  MAX_NAME_LENGTH = 120
  MAX_EMAIL_LENGTH = 254

  def initialize(profile:, name:, phone:, starts_at:, email: nil, duration: nil, location_type: nil) # rubocop:disable Metrics/ParameterLists
    @profile = profile
    @raw = { name: name, phone: phone, starts_at: starts_at, email: email, duration: duration, location_type: location_type }
  end

  def validate!
    raise ArgumentError, 'invalid_name' if name.blank?
    raise ArgumentError, 'invalid_phone' if phone.blank?
    raise ArgumentError, 'invalid_email' if @raw[:email].present? && email.blank?

    starts_at
    raise ArgumentError, 'invalid_duration' unless profile.durations.include?(duration_minutes)

    location
  end

  def name
    @name ||= clean_text(@raw[:name]).first(MAX_NAME_LENGTH).strip
  end

  def phone
    @phone ||= Crm::BookingV2::PhoneLookup.normalize(@raw[:phone], region: Crm::BookingV2::PhoneLookup.region_for(profile.resolved_timezone))
  end

  def phone_candidates
    @phone_candidates ||= Crm::BookingV2::PhoneLookup.candidates(phone)
  end

  def email
    @email ||= clean_email(@raw[:email])
  end

  def starts_at
    @starts_at ||= Time.iso8601(@raw[:starts_at].to_s)
  rescue ArgumentError
    raise ArgumentError, 'invalid_starts_at'
  end

  def duration_minutes
    @duration_minutes ||= @raw[:duration].nil? ? profile.duration_minutes : Integer(@raw[:duration].to_s, exception: false)
  end

  # O local pedido precisa ser um dos locais da página; sem pedido, o primeiro.
  def location
    @location ||= begin
      options = Array(profile.locations).select { |item| item.is_a?(Hash) }
      wanted = @raw[:location_type].to_s.presence || options.first&.dig('type')
      options.find { |item| item['type'] == wanted } || (raise ArgumentError, 'invalid_location')
    end
  end

  private

  attr_reader :profile

  # Texto puro: sem tag HTML e sem caractere de controle (vira espaço). O strip_tags devolve entidades ("&" vira
  # "&amp;"); como gravamos texto, e não HTML, desfazemos a entidade: quem mostra (Vue, views) já escapa.
  def clean_text(value)
    plain = CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(value.to_s))
    plain.each_char.map { |char| char.ord < 32 || char.ord == 127 ? ' ' : char }.join
  end

  def clean_email(value)
    normalized = value.to_s.strip.downcase
    return if normalized.blank? || normalized.length > MAX_EMAIL_LENGTH

    address = Mail::Address.new(normalized).address
    normalized if address == normalized && address.include?('@') && address.split('@').last.include?('.')
  rescue Mail::Field::ParseError
    nil
  end
end
