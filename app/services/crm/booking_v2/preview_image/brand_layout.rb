# Desenho A (#1282), o padrão: fundo na cor da página, logo num cartão branco, nome do atendimento e a chamada.
class Crm::BookingV2::PreviewImage::BrandLayout < Crm::BookingV2::PreviewImage::Layout
  MARK_TOP = MARGIN - 16
  LOGO_BOX = [300, 76].freeze
  LOGO_PADDING = [28, 22].freeze
  LOGO_RADIUS = 24
  BADGE = 120
  BADGE_RING = 6
  TITLE_GAP = 44
  TITLE_WIDTH = 940
  TITLE_SIZES = [84, 76, 68, 60, 54, 48].freeze

  private

  def draw
    @canvas = Canvas.new(from: Palette.mix(brand, Palette::WHITE, 0.1), to: Palette.mix(brand, [0, 0, 0], 0.34))
    decorate
    top = mark
    title(Palette::WHITE, at: [MARGIN, top], box: [TITLE_WIDTH, pill_top - top - TITLE_GAP], sizes: TITLE_SIZES)
    aside = MARGIN + pill(fill: Palette::WHITE, ink: brand) + 36
    line(facts_text, Palette::WHITE, at: [aside, pill_top + 26], width: Canvas::WIDTH - MARGIN - aside, style: { opacity: 0.86 })
  end

  def decorate
    canvas.disc([1110, 20], 330, Palette::WHITE, opacity: 0.07)
    canvas.disc([1110, 20], 210, Palette::WHITE, opacity: 0.06)
    canvas.disc([980, 690], 250, Palette::WHITE, opacity: 0.05)
  end

  # Logo (ou, sem logo, a foto da página). Devolve onde o título começa.
  def mark
    return logo_card if art.logo
    return photo_badge if art.photo

    MARGIN + 8
  end

  def logo_card
    logo = Canvas.picture(art.logo, size: LOGO_BOX)
    pad_x, pad_y = LOGO_PADDING
    card = [logo.width + (pad_x * 2), logo.height + (pad_y * 2)]
    canvas.shadow(card, LOGO_RADIUS, at: [MARGIN, MARK_TOP], opacity: 0.2)
    canvas.rounded(card, LOGO_RADIUS, Palette::WHITE, at: [MARGIN, MARK_TOP])
    canvas.picture(logo, Canvas.rounded_mask([logo.width, logo.height], 6), at: [MARGIN + pad_x, MARK_TOP + pad_y])
    MARK_TOP + card.last + TITLE_GAP
  end

  def photo_badge
    canvas.rounded([BADGE, BADGE], BADGE / 2, Palette::WHITE, at: [MARGIN, MARK_TOP])
    round_photo(art.photo, BADGE - (BADGE_RING * 2), at: [MARGIN + BADGE_RING, MARK_TOP + BADGE_RING])
    MARK_TOP + BADGE + TITLE_GAP
  end
end
