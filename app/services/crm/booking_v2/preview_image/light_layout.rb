# Desenho C (#1282): claro, com um ícone de agenda. Para a página sem logo nem foto. O ícone não tem dia nem hora:
# só bolinhas, uma delas na cor da página.
#
# Sem título (`Art#title` vazio) desenha só o ícone, no centro: é assim que se gera a imagem neutra fixa de
# `public/booking-preview.png`, servida quando não há página para mostrar.
class Crm::BookingV2::PreviewImage::LightLayout < Crm::BookingV2::PreviewImage::Layout
  TITLE_SIZES = [76, 68, 60, 54, 48, 42].freeze
  ICON = 320
  ICON_SIZE = [ICON, ICON].freeze
  ICON_RADIUS = 44
  HEADER = 84
  RINGS = [0.3, 0.7].freeze
  RING_SIZE = [18, 56].freeze
  DOT = 34
  DOT_SIZE = [DOT, DOT].freeze
  COLUMNS = 4
  ROWS = 3
  CHOSEN = [1, 2].freeze
  # De uma bolinha à seguinte, com as bolinhas espalhadas por igual dentro do cartão.
  DOT_STEP_X = DOT + ((ICON - 72 - (DOT * COLUMNS)) / (COLUMNS - 1).to_f)
  DOT_STEP_Y = DOT + ((ICON - HEADER - 68 - (DOT * ROWS)) / (ROWS - 1).to_f)

  private

  def draw
    @canvas = Canvas.new(from: Palette::WHITE, to: Palette.mix(Palette::PAPER, brand, 0.1))
    center = [icon_left + (ICON / 2), icon_top + (ICON / 2)]
    canvas.disc(center, 300, brand, opacity: 0.06)
    canvas.disc(center, 215, brand, opacity: 0.06)
    calendar
    text_column unless neutral?
  end

  def neutral?
    art.title.blank?
  end

  def icon_left
    neutral? ? (Canvas::WIDTH - ICON) / 2 : Canvas::WIDTH - MARGIN - ICON
  end

  def icon_top
    neutral? ? ((Canvas::HEIGHT - ICON) / 2) + 10 : 132
  end

  def text_column
    width = icon_left - MARGIN - 64
    canvas.rounded([72, 8], 4, brand, at: [MARGIN, MARGIN + 6])
    top = MARGIN + 46
    used = title(Palette::INK, at: [MARGIN, top], box: [width, pill_top - top - 96], sizes: TITLE_SIZES)
    line(facts_text, Palette::MUTED, at: [MARGIN, top + used + 36], width: width)
    brand_pill
  end

  def calendar
    canvas.shadow(ICON_SIZE, ICON_RADIUS, at: [icon_left, icon_top], blur: 30, drop: 22, opacity: 0.18)
    header
    rings
    dots
  end

  # Faixa de cima na cor da página: o cartão inteiro na cor, coberto de branco da faixa para baixo.
  def header
    below = [icon_left, icon_top + HEADER]
    canvas.rounded(ICON_SIZE, ICON_RADIUS, accent, at: [icon_left, icon_top])
    canvas.rounded([ICON, ICON - HEADER], ICON_RADIUS, Palette::WHITE, at: below)
    canvas.rounded([ICON, ICON_RADIUS], 0, Palette::WHITE, at: below)
  end

  def rings
    color = Palette.mix(brand, [0, 0, 0], 0.35)
    RINGS.each do |position|
      canvas.rounded(RING_SIZE, RING_SIZE.first / 2, color, at: [icon_left + (ICON * position) - (RING_SIZE.first / 2), icon_top - 22])
    end
  end

  def dots
    ROWS.times do |row|
      COLUMNS.times { |column| dot(row, column) }
    end
  end

  def dot(row, column)
    at = [icon_left + 36 + (column * DOT_STEP_X), icon_top + HEADER + 34 + (row * DOT_STEP_Y)]
    return canvas.rounded(DOT_SIZE, DOT / 2, accent, at: at) if [row, column] == CHOSEN

    canvas.rounded(DOT_SIZE, 10, Palette.mix(Palette::PAPER, Palette::MUTED, 0.2), at: at)
  end
end
