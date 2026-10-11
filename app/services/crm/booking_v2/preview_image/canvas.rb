# Tela da imagem de prévia do link de agendamento (#1282): 1200×630, desenhada só com libvips (o que a imagem de
# produção já tem). Formas saem de máscaras calculadas (borda suave, sem SVG: o carregador de SVG fica bloqueado em
# produção por `VIPS_BLOCK_UNTRUSTED`) e o texto sai do Pango com a fonte Inter que vai junto no repositório
# (`lib/assets/fonts/inter`, licença OFL), para o desenho não depender de fonte instalada na máquina.
#
# Posições e tamanhos são pares: `at: [esquerda, topo]`, `size: [largura, altura]`.
#
# A libvips é carregada no primeiro uso: onde ela não existe, quem chama recebe LoadError e serve a imagem neutra.
class Crm::BookingV2::PreviewImage::Canvas
  WIDTH = 1200
  HEIGHT = 630
  FONT_DIR = Rails.root.join('lib/assets/fonts/inter')
  FONTS = { bold: ['Inter Bold', 'Inter-Bold.ttf'], medium: ['Inter Medium', 'Inter-Medium.ttf'] }.freeze
  ELLIPSIS = '…'.freeze
  # Folga entre as linhas de um texto que quebra, em fração do tamanho da letra.
  LINE_GAP = 0.1
  # A cada tentativa de fazer o texto caber, ele perde esta fração do comprimento.
  TRUNCATE_STEP = 0.85
  # Imagem enviada pela conta (logo, foto): recusada antes de decodificar se for uma bomba de descompressão. 16
  # milhões de pixels cobrem a foto de celular (12 MP) e limitam a memória de um desenho a dezenas de MB.
  MAX_SOURCE_PIXELS = 16_000_000
  WHITE = [255, 255, 255].freeze
  SHADOW_COLOR = [15, 23, 42].freeze
  SHADOW = { blur: 24, drop: 14, opacity: 0.16 }.freeze

  class UnusableImage < StandardError; end

  def self.load!
    require 'image_processing/vips'
  end

  # Máscara (0..255) de um retângulo de cantos redondos com borda suave. `radius` = metade do lado faz um círculo.
  def self.rounded_mask(size, radius)
    load!
    grid = Vips::Image.xyz(*size)
    edge_x = edge(grid[0], size.first, radius)
    edge_y = edge(grid[1], size.last, radius)
    outside = (((above_zero(edge_x)**2) + (above_zero(edge_y)**2))**0.5)
    coverage(outside + below_zero(larger(edge_x, edge_y)) - radius)
  end

  # Num eixo: quanto cada pixel passa do miolo reto do retângulo (o lado menos o raio dos cantos).
  def self.edge(axis, length, radius)
    (axis - ((length - 1) / 2.0)).abs - ((length / 2.0) - radius)
  end

  # Aritmética de imagem, pixel a pixel: max(valor, 0), min(valor, 0) e max(a, b).
  def self.above_zero(image)
    (image + image.abs) / 2
  end

  def self.below_zero(image)
    (image - image.abs) / 2
  end

  def self.larger(first, second)
    (first + second + (first - second).abs) / 2
  end

  # Distância até a borda (negativa = dentro) vira cobertura do pixel: 1 px de transição, sem serrilhado.
  def self.coverage(distance)
    inside = above_zero((distance * -1) + 0.5)
    (((above_zero((inside * -1) + 1) * -1) + 1) * 255).cast(:uchar)
  end

  # O texto é escrito por uma pessoa: escapado, porque o Pango leria `<` e `&` como marcação.
  def self.text_mask(text, font:, size:, width: nil)
    load!
    family, file = FONTS.fetch(font)
    options = { font: "#{family} #{size}", fontfile: FONT_DIR.join(file).to_s, dpi: 72 }
    options = options.merge(width: width, spacing: (size * LINE_GAP).round) if width
    Vips::Image.text(CGI.escapeHTML(text.to_s), **options)
  end

  # O maior tamanho de `sizes` em que o texto cabe na caixa (`box` = [largura, altura]); se nem o menor couber,
  # corta com reticências.
  def self.fitted_text(text, font:, sizes:, box:)
    sizes.each do |size|
      mask = text_mask(text, font: font, size: size, width: box.first)
      return mask if fits?(mask, box)
    end
    truncated_text(text, font: font, size: sizes.last, box: box)
  end

  def self.truncated_text(text, font:, size:, box:)
    chars = text.to_s.chars
    loop do
      chars = chars.first((chars.size * TRUNCATE_STEP).floor)
      mask = text_mask("#{chars.join.strip}#{ELLIPSIS}", font: font, size: size, width: box.first)
      return mask if chars.empty? || fits?(mask, box)
    end
  end

  def self.fits?(mask, box)
    mask.width <= box.first && mask.height <= box.last
  end

  # Logo ou foto da conta, reduzida para caber em `size` (ou recortada no centro, com `crop`), em RGB.
  def self.picture(bytes, size:, crop: false)
    load!
    header = Vips::Image.new_from_buffer(bytes, '')
    raise UnusableImage, 'too many pixels' if header.width * header.height > MAX_SOURCE_PIXELS

    options = crop ? { height: size.last, crop: :centre } : { height: size.last, size: :down }
    image = Vips::Image.thumbnail_buffer(bytes, size.first, **options).colourspace(:srgb)
    image = image.flatten(background: WHITE) if image.has_alpha?
    image.extract_band(0, n: 3).cast(:uchar)
  rescue Vips::Error
    raise UnusableImage, 'unreadable image'
  end

  # Fundo em degradê diagonal, de `from` (canto de cima) a `to` (canto de baixo).
  def initialize(from:, to:)
    self.class.load!
    grid = Vips::Image.xyz(WIDTH, HEIGHT)
    ramp = ((grid[0] * (0.55 / WIDTH)) + (grid[1] * (0.45 / HEIGHT)))
    steps = to.zip(from).map { |last, first| last - first }
    @image = ramp.linear(steps, from).cast(:uchar).copy(interpretation: :srgb).bandjoin(255)
  end

  # Pinta `color` onde a máscara cobre, com o canto superior esquerdo em `at`.
  def paint(mask, color, at:, opacity: 1.0)
    alpha = opacity >= 1 ? mask : (mask * opacity).cast(:uchar)
    layer = mask.new_from_image(color).cast(:uchar).copy(interpretation: :srgb).bandjoin(alpha)
    @image = @image.composite2(layer, :over, x: at.first.round, y: at.last.round)
    self
  end

  def rounded(size, radius, color, at:, opacity: 1.0)
    paint(self.class.rounded_mask(size, radius), color, at: at, opacity: opacity)
  end

  # Círculo que pode sair da tela (enfeite de fundo): a máscara é calculada na tela inteira.
  def disc(center, radius, color, opacity:)
    grid = Vips::Image.xyz(WIDTH, HEIGHT)
    distance = ((((grid[0] - center.first)**2) + ((grid[1] - center.last)**2))**0.5)
    paint(self.class.coverage(distance - radius), color, at: [0, 0], opacity: opacity)
  end

  # Sombra suave de um cartão de cantos redondos em `at`. `soft` troca o padrão de `SHADOW`.
  def shadow(size, radius, at:, **soft)
    look = SHADOW.merge(soft)
    pad = look[:blur] * 3
    mask = self.class.rounded_mask(size, radius).embed(pad, pad, size.first + (pad * 2), size.last + (pad * 2)).gaussblur(look[:blur])
    paint(mask, SHADOW_COLOR, at: [at.first - pad, at.last - pad + look[:drop]], opacity: look[:opacity])
  end

  # Imagem RGB recortada pela máscara (foto redonda, logo de cantos redondos).
  def picture(image, mask, at:)
    @image = @image.composite2(image.bandjoin(mask).copy(interpretation: :srgb), :over, x: at.first.round, y: at.last.round)
    self
  end

  def png
    @image.flatten(background: WHITE).pngsave_buffer(compression: 9, strip: true)
  end
end
