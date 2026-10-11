# Desenho B (#1282): link de uma pessoa que tem foto. Foto redonda de quem atende, "Com <nome>", o serviço, e
# duração e local em etiquetas.
class Crm::BookingV2::PreviewImage::PersonLayout < Crm::BookingV2::PreviewImage::Layout
  PHOTO = 320
  PHOTO_SIZE = [PHOTO, PHOTO].freeze
  RING = 12
  PHOTO_AT = [MARGIN, (Canvas::HEIGHT - PHOTO) / 2].freeze
  COLUMN = MARGIN + PHOTO + 76
  COLUMN_WIDTH = Canvas::WIDTH - MARGIN - COLUMN
  TITLE_SIZES = [64, 58, 52, 46, 40].freeze
  CHIP_HEIGHT = 56
  CHIP_PADDING = 22
  CHIP_GAP = 14

  private

  def draw
    @canvas = Canvas.new(from: Palette::WHITE, to: Palette.mix(Palette::PAPER, brand, 0.1))
    canvas.rounded([16, Canvas::HEIGHT], 0, accent, at: [0, 0])
    portrait
    chips(text_column)
    brand_pill(left: COLUMN)
  end

  # "Com <nome>" e o serviço. Devolve onde as etiquetas começam.
  def text_column
    top = MARGIN + 4
    top += line(art.host_line, brand, at: [COLUMN, top], width: COLUMN_WIDTH, style: { size: 32, font: :bold }) + 26
    top + title(Palette::INK, at: [COLUMN, top], box: [COLUMN_WIDTH, pill_top - top - 120], sizes: TITLE_SIZES) + 34
  end

  def portrait
    left, top = PHOTO_AT
    canvas.disc([left + (PHOTO / 2), top + (PHOTO / 2)], (PHOTO / 2) + 46, brand, opacity: 0.08)
    canvas.shadow(PHOTO_SIZE, PHOTO / 2, at: PHOTO_AT, blur: 26, drop: 18, opacity: 0.2)
    canvas.rounded(PHOTO_SIZE, PHOTO / 2, Palette::WHITE, at: PHOTO_AT)
    round_photo(art.photo, PHOTO - (RING * 2), at: [left + RING, top + RING])
  end

  # Etiquetas de duração e local, lado a lado; a que não couber na linha fica de fora.
  def chips(top)
    left = COLUMN
    art.facts.compact_blank.each do |fact|
      label = Canvas.text_mask(fact, font: :medium, size: 26)
      width = label.width + (CHIP_PADDING * 2)
      break if left + width > COLUMN + COLUMN_WIDTH

      chip(label, width, at: [left, top])
      left += width + CHIP_GAP
    end
  end

  def chip(label, width, at:)
    canvas.rounded([width, CHIP_HEIGHT], CHIP_HEIGHT / 2, Palette.mix(Palette::WHITE, brand, 0.1), at: at)
    canvas.paint(label, Palette.mix(brand, Palette::INK, 0.35), at: [at.first + CHIP_PADDING, at.last + ((CHIP_HEIGHT - label.height) / 2.0)])
  end
end
