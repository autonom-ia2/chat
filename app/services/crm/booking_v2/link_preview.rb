# Prévia do link de agendamento (#1282): o que o WhatsApp mostra junto do link — título, descrição e imagem
# (Open Graph), postos no HTML que o servidor entrega em `/a/…`, `/book/…` e `/b/…`.
#
# Só dados da PÁGINA: nome do atendimento, duração, local e quem atende (no link de uma pessoa). Nunca nome,
# telefone ou qualquer dado do cliente, nem no link do cliente `/b/<código>`: lá a prévia é a da página dona do
# convite. Sem dia nem hora: a prévia fica em cache em quem a mostra.
#
# NEUTRA (`neutral?`) quando a página não pode ser marcada agora: não existe, é antiga, está pausada, a conta está
# sem a flag, o responsável não atende mais, ou a visita é uma prévia de página despublicada. A prévia neutra é a
# mesma para todos esses casos (nome da instalação, sem descrição, imagem fixa), para não contar qual deles é.
class Crm::BookingV2::LinkPreview
  TITLE_LENGTH = 60
  DESCRIPTION_LENGTH = 90
  SEPARATOR = ' · '.freeze

  attr_reader :page

  def self.for_slug(slug)
    new(::Crm::BookingV2::PublicPage.find(slug))
  end

  def self.for_invite_code(code)
    invite = ::Crm::BookingInvite.includes(:booking_link, :booking_profile).find_by(code: code.to_s)
    return new(nil) if invite.nil? || !invite.active?

    for_slug(invite.booking_link&.slug || invite.booking_profile.slug)
  end

  def initialize(page)
    @page = page
  end

  def neutral?
    !page&.bookable?
  end

  def title
    return if neutral?

    profile.title.to_s.squish.truncate(TITLE_LENGTH, separator: ' ', omission: '…').presence
  end

  def description
    return if neutral?

    [host_line, *facts, translate('description_call')].compact_blank.join(SEPARATOR).truncate(DESCRIPTION_LENGTH, omission: '…')
  end

  def image_url
    base = ::Crm::BookingV2::ShortLink.base_url
    return "#{base}/#{::Crm::BookingV2::PreviewImage::NEUTRAL_FILE}" if neutral?

    "#{base}/book/#{page.slug}/preview/#{::Crm::BookingV2::PreviewImage::Content.new(self).version}.png"
  end

  # "Com Ana": só no link de uma pessoa (página com um link por pessoa).
  def host_line
    name = page.link && page.host&.available_name.presence
    translate('with_host', name: name) if name
  end

  # Duração e primeiro local, como texto pronto.
  def facts
    [duration_text, location_text].compact_blank
  end

  def call
    translate('call')
  end

  def profile
    page.profile
  end

  def locale
    ::Crm::BookingV2::LocationLabel.locale(page&.account)
  end

  private

  def duration_text
    hours, minutes = profile.duration_minutes.to_i.divmod(60)
    return translate('minutes', count: minutes) if hours.zero?
    return translate('hours', count: hours) if minutes.zero?

    translate('hours_minutes', hours: hours, minutes: minutes)
  end

  def location_text
    first = Array(profile.locations).find { |item| item.is_a?(Hash) }
    ::Crm::BookingV2::LocationLabel.for(first, account: page.account).to_s.squish if first
  end

  def translate(key, **)
    I18n.t("crm.booking_v2.link_preview.#{key}", locale: locale, **)
  end
end
