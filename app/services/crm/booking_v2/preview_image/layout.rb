# Base dos três desenhos da imagem de prévia (#1282): margens, o botão da chamada, o título que encolhe até caber e
# a linha de duração e local. Cada desenho só posiciona as peças.
class Crm::BookingV2::PreviewImage::Layout
  Canvas = Crm::BookingV2::PreviewImage::Canvas
  Palette = Crm::BookingV2::PreviewImage::Palette

  MARGIN = 88
  PILL_HEIGHT = 84
  PILL_PADDING = 40
  PILL_TEXT_SIZE = 34
  PILL_BORDER = 3
  FAINT = 1.2
  ARROW = '→'.freeze
  FACT_SEPARATOR = '  ·  '.freeze
  LINE_STYLE = { size: 30, font: :medium, opacity: 1.0 }.freeze

  def initialize(art)
    @art = art
    @brand = Palette.brand(art.color)
    @fill = Palette.fill(art.color)
    @on = Palette.on(@fill)
    # Traços na cor da página sobre branco (a faixa do ícone, a barra lateral): a cor exata, a não ser que ela quase
    # não se distinga do branco; aí vai a versão legível.
    @accent = Palette.contrast(@fill, Palette::WHITE) < FAINT ? @brand : @fill
  end

  def png
    draw
    canvas.png
  end

  private

  attr_reader :art, :brand, :fill, :on, :accent, :canvas

  def pill_top
    Canvas::HEIGHT - MARGIN - PILL_HEIGHT
  end

  # Botão da chamada ("Escolher horário →"). `border`: contorno, para botão de cor clara sobre fundo claro não sumir
  # (o botão da página pública faz o mesmo). Devolve a largura, para o que vier ao lado.
  def pill(fill:, ink:, left: MARGIN, border: nil)
    label = Canvas.text_mask("#{art.call}  #{ARROW}", font: :bold, size: PILL_TEXT_SIZE)
    width = label.width + (PILL_PADDING * 2)
    pill_shape(width, fill, border, left)
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

  def pill_shape(width, fill, border, left)
    canvas.rounded([width, PILL_HEIGHT], PILL_HEIGHT / 2, border || fill, at: [left, pill_top])
    return if border.nil?

    inner = [width - (PILL_BORDER * 2), PILL_HEIGHT - (PILL_BORDER * 2)]
    canvas.rounded(inner, inner.last / 2, fill, at: [left + PILL_BORDER, pill_top + PILL_BORDER])
  end

  # Botão na cor da página sobre fundo claro (desenhos B e C): a cor exata, o texto por cima claro ou escuro e o
  # contorno na versão legível da cor.
  def brand_pill(left: MARGIN)
    pill(fill: fill, ink: on, left: left, border: brand)
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
