# Base dos três desenhos da imagem de prévia (#1282): margens, o botão da chamada, o título que encolhe até caber e
# a linha de duração e local. Cada desenho só posiciona as peças.
class Crm::BookingV2::PreviewImage::Layout
  Canvas = Crm::BookingV2::PreviewImage::Canvas
  Palette = Crm::BookingV2::PreviewImage::Palette

  MARGIN = 88
  PILL_HEIGHT = 84
  PILL_PADDING = 40
  PILL_TEXT_SIZE = 34
  ARROW = '→'.freeze
  FACT_SEPARATOR = '  ·  '.freeze
  LINE_STYLE = { size: 30, font: :medium, opacity: 1.0 }.freeze

  def initialize(art)
    @art = art
    @brand = Palette.brand(art.color)
  end

  def png
    draw
    canvas.png
  end

  private

  attr_reader :art, :brand, :canvas

  def pill_top
    Canvas::HEIGHT - MARGIN - PILL_HEIGHT
  end

  # Botão da chamada ("Escolher horário →"). Devolve a largura, para o que vier ao lado.
  def pill(fill:, ink:, left: MARGIN)
    label = Canvas.text_mask("#{art.call}  #{ARROW}", font: :bold, size: PILL_TEXT_SIZE)
    width = label.width + (PILL_PADDING * 2)
    canvas.rounded([width, PILL_HEIGHT], PILL_HEIGHT / 2, fill, at: [left, pill_top])
    canvas.paint(label, ink, at: [left + PILL_PADDING, pill_top + ((PILL_HEIGHT - label.height) / 2.0)])
    width
  end

  # Título que encolhe até caber em `box` ([largura, altura]). Devolve a altura que ocupou.
  def title(color, at:, box:, sizes:)
    return 0 if art.title.blank?

    mask = Canvas.fitted_text(art.title, font: :bold, sizes: sizes, box: box)
    canvas.paint(mask, color, at: at)
    mask.height
  end

  def facts_text
    art.facts.compact_blank.join(FACT_SEPARATOR)
  end

  # Uma linha só, cortada com reticências se não couber. `style` troca o padrão de `LINE_STYLE`. Devolve a altura.
  def line(text, color, at:, width:, style: {})
    return 0 if text.blank?

    look = LINE_STYLE.merge(style)
    mask = Canvas.fitted_text(text, font: look[:font], sizes: [look[:size]], box: [width, (look[:size] * 1.5).round])
    canvas.paint(mask, color, at: at, opacity: look[:opacity])
    mask.height
  end

  # Foto recortada em círculo, com o canto superior esquerdo em `at`.
  def round_photo(bytes, diameter, at:)
    photo = Canvas.picture(bytes, size: [diameter, diameter], crop: true)
    canvas.picture(photo, Canvas.rounded_mask([photo.width, photo.height], photo.width / 2), at: at)
  end
end
