# JSON público da página de agendamento v2 (#1189, RA-05): só o que o cliente precisa para marcar. Responsável por
# nome e foto; nunca e-mail, id interno, caixa ou URL privada de local (o link de reunião só sai na confirmação).
#
# `locations[].label`: o rótulo que o dono escreveu ou o nome leigo do catálogo do fork (`LocationLabel`), no idioma
# da conta. `requires_email`: Meet e Teams mandam o convite por e-mail, então o formulário pede e-mail. `address`: só
# do local presencial, que o dono publicou para o cliente saber aonde ir antes de confirmar.
#
# `timezone`: nome IANA do fuso da página (o navegador não entende os nomes do Rails, como "Brasilia"). `weekdays`: dias
# da semana em que a página atende (0 = domingo ... 6 = sábado), para a página não oferecer dia fechado.
# `closed_dates` (#1195, J2-A8): feriados nacionais (`Crm::Calendar::Holidays`) da janela, de hoje a
# `booking_window_days` no fuso da página, como YYYY-MM-DD. Só com `close_holidays` ligado: são os dias em que `Slots`
# não oferece horário, e a página os trata como dia fechado em vez de deixar o cliente tocar à toa.
# `notices_enabled` (#1192): a página tem caixa de avisos utilizável; a tela mostra o aviso de consentimento.
class Crm::BookingV2::PublicPageSerializer
  include Rails.application.routes.url_helpers

  FORM_TOKEN_TTL = 2.hours
  EMAIL_LOCATIONS = Crm::BookingPageSettings::CALENDAR_LOCATIONS.keys.freeze
  DIGITS = '0123456789'.chars.freeze

  def self.whatsapp_url(profile)
    digits = profile.contact_phone.to_s.chars.select { |char| DIGITS.include?(char) }.join
    "https://wa.me/#{digits}" if digits.present?
  end

  def self.form_token(slug)
    Crm::BookingV2::Tokens.generate('form', { 's' => slug, 't' => Time.current.to_i }, expires_in: FORM_TOKEN_TTL)
  end

  def initialize(page)
    @page = page
    @profile = page.profile
  end

  def paused
    { slug: page.slug, paused: true, title: profile.title, brand: brand, contact_whatsapp_url: self.class.whatsapp_url(profile) }
  end

  def full
    {
      slug: page.slug, paused: false, preview: page.preview?, title: profile.title, description: profile.description,
      agent_name: host_name, agent_photo_url: page.host&.avatar_url.presence, brand: brand, locations: locations,
      contact_whatsapp_url: self.class.whatsapp_url(profile)
    }.merge(schedule, form)
  end

  private

  attr_reader :page, :profile

  def schedule
    {
      duration_minutes: profile.duration_minutes, durations: profile.durations, timezone: page.time_zone&.tzinfo&.name,
      booking_window_days: profile.booking_window_days, weekdays: profile.weekdays.sort, closed_dates: closed_dates
    }
  end

  def closed_dates
    return [] unless profile.close_holidays?

    today = Time.current.in_time_zone(page.time_zone || 'UTC').to_date
    (today..(today + profile.booking_window_days)).select { |day| Crm::Calendar::Holidays.holiday?(day) }.map(&:iso8601)
  end

  def form
    { form_token: self.class.form_token(page.slug), captcha_site_key: captcha_site_key, notices_enabled: profile.notices_usable? }
  end

  def host_name
    page.host&.available_name.presence || profile.title
  end

  def brand
    data = profile.brand.to_h
    {
      color: data['color'].presence, headline: data['headline'].presence,
      logo_url: attachment_url(profile.logo), photo_url: attachment_url(profile.photo)
    }
  end

  def locations
    Array(profile.locations).select { |item| item.is_a?(Hash) }.map do |item|
      { type: item['type'], label: Crm::BookingV2::LocationLabel.for(item, account: profile.account),
        requires_email: EMAIL_LOCATIONS.include?(item['type']), address: in_person_address(item) }.compact
    end
  end

  def in_person_address(item)
    item['address'].presence if item['type'] == 'in_person'
  end

  # Sem chave de servidor o hCaptcha não é conferido (ChatwootCaptcha aceita tudo), então a página nem o mostra.
  def captcha_site_key
    return if GlobalConfigService.load('HCAPTCHA_SERVER_KEY', '').blank?

    GlobalConfigService.load('HCAPTCHA_SITE_KEY', '').presence
  end

  def attachment_url(attachment)
    return unless attachment.attached?

    url_for(attachment)
  end
end
