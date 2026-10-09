# JSON público da página de agendamento v2 (#1189, RA-05): só o que o cliente precisa para marcar. Responsável por
# nome e foto; nunca e-mail, id interno, caixa ou URL privada de local (o link de reunião só sai na confirmação).
#
# `locations[].label`: o rótulo que o dono escreveu ou o nome leigo do catálogo do fork (`LocationLabel`), no idioma
# da conta. `requires_email`: Meet e Teams mandam o convite por e-mail, então o formulário pede e-mail.
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
      duration_minutes: profile.duration_minutes, durations: profile.durations, timezone: profile.resolved_timezone,
      booking_window_days: profile.booking_window_days
    }
  end

  def form
    { form_token: self.class.form_token(page.slug), captcha_site_key: captcha_site_key, notices_enabled: false }
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
        requires_email: EMAIL_LOCATIONS.include?(item['type']) }
    end
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
