# A logo para fundo escuro, a partir da logo que a pessoa enviou (#1295). Só transformação de pixel, com libvips (a
# mesma do `image_processing`); nada de IA: a forma da marca fica exatamente a que chegou. A ideia vem do motor do
# Studio (`studio_api/logo_engine.py`): tirar o fundo sólido a partir das bordas, medir os pixels visíveis e decidir.
#
# O que sai (`Outcome#source`):
#
# - `same`      a logo já se lê sobre o cartão escuro (tem transparência e quase nada escuro): usa a mesma, não gera;
# - `generated` gera um PNG: a logo recortada do fundo sólido, a mesma em tons invertidos (preto e cinza viram branco
#               e cinza) ou a silhueta branca de uma logo de uma cor só. A transparência é mantida;
# - `plate`     não dá para gerar sem estragar a marca (imagem sem transparência e sem fundo sólido, como foto ou JPEG
#               chapado; logo de várias cores com partes escuras): a página escura mostra a original numa placa clara.
#
# Nunca levanta erro: arquivo ilegível, imagem grande demais ou libvips ausente caem em `plate`, com o motivo em
# `reason` (quem chama, `LogoDark`, põe a decisão e o motivo no log). A logo enviada nunca deixa de ser salva por causa daqui.
module Crm::BookingV2::LogoDarkEngine
  # Acima disso a imagem nem é aberta (um PNG de 2 MB pode esconder centenas de megapixels).
  MAX_PIXELS = 16_000_000
  # A conta é feita numa cópia de até 800 px de lado: sobra para a logo de 56 px de altura em tela de 3x, e o tempo
  # e a memória ficam limitados seja qual for o arquivo.
  WORK_SIDE = 800
  # Menor que isso não é logo (e as contas de vizinhança, de 3 x 3 pixels, nem cabem).
  MIN_SIDE = 3
  MAX_OUTPUT_BYTES = Crm::BookingPageSettings::MAX_IMAGE_BYTES
  # Alpha acima disso conta como pixel visível.
  VISIBLE_ALPHA = 16
  # Menos que isso de pixels transparentes = imagem sem transparência.
  MIN_TRANSPARENT = 0.02
  # Fundo sólido: os quatro cantos parecidos entre si e quase toda a borda parecida com eles (distância por canal).
  CORNER_TOLERANCE = 18
  BACKGROUND_TOLERANCE = 24
  MIN_BORDER_MATCH = 0.9
  # O cartão do tema escuro (`--bk-card` em public_booking_v2/assets/_booking-theme.scss) e o contraste mínimo para
  # um pedaço da logo contar como legível sobre ele (3:1, o mínimo do WCAG para elemento gráfico).
  DARK_CARD = [23, 25, 30].freeze
  MIN_CONTRAST = 3.0
  # Até 10% de pixels pouco legíveis: a logo já serve no escuro.
  MAX_LOW_FOR_SAME = 0.10
  # Logo sem cor (preto, cinza, branco): diferença entre os canais de até 28 em 95% dos pixels visíveis.
  GRAY_CHROMA = 28
  MIN_GRAY = 0.95
  # Depois de inverter os tons, no máximo 35% pode continuar pouco legível.
  MAX_LOW_AFTER_INVERT = 0.35
  # Logo de uma cor só: 90% dos pixels visíveis a até 48 por canal da cor média.
  ONE_COLOR_TOLERANCE = 48
  MIN_ONE_COLOR = 0.9
  WHITE = [255, 255, 255].freeze
  LUMINANCE_WEIGHTS = [[0.2126, 0.7152, 0.0722]].freeze
  # Luminância (0 a 1) a partir da qual um pixel tem MIN_CONTRAST sobre o cartão escuro.
  MIN_LUMINANCE = begin
    linear = DARK_CARD.map do |value|
      channel = value / 255.0
      channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
    end
    card = LUMINANCE_WEIGHTS.first.zip(linear).sum { |factor, channel| factor * channel }
    (MIN_CONTRAST * (card + 0.05)) - 0.05
  end

  Outcome = Data.define(:source, :png, :reason)

  module_function

  def call(bytes)
    require 'image_processing/vips'
    header = Vips::Image.new_from_buffer(bytes, '', access: :sequential)
    return plate(:too_large) if header.width * header.height > MAX_PIXELS

    decide(prepare(bytes))
  rescue StandardError, LoadError => e
    Rails.logger.warn("[booking] logo para fundo escuro não gerada: #{e.class}: #{e.message.to_s.first(200)}")
    plate(:unreadable)
  end

  def plate(reason)
    Outcome.new(source: 'plate', png: nil, reason: reason)
  end

  def generated(image, reason)
    png = image.pngsave_buffer(compression: 9, strip: true)
    return plate(:output_too_large) if png.bytesize > MAX_OUTPUT_BYTES

    Outcome.new(source: 'generated', png: png, reason: reason)
  end

  # Cópia pequena, em pé (EXIF), em sRGB de 8 bits com canal alpha, já na memória.
  def prepare(bytes)
    small = Vips::Image.thumbnail_buffer(bytes, WORK_SIDE, height: WORK_SIDE, size: :down)
    small = small.colourspace(:srgb).cast(:uchar)
    small = small.bandjoin(255) unless small.has_alpha?
    small.copy_memory
  end

  def decide(image)
    return plate(:too_small) if image.width < MIN_SIDE || image.height < MIN_SIDE

    removed = false
    if transparent_fraction(image) < MIN_TRANSPARENT
      cutout = without_solid_background(image)
      return plate(:no_transparency) if cutout.nil? || transparent_fraction(cutout) < MIN_TRANSPARENT

      image = cutout
      removed = true
    end

    weight = visible_weight(image)
    return plate(:empty) if weight.avg.zero?

    choose(image, weight, removed)
  end

  def choose(image, weight, removed)
    rgb = image.extract_band(0, n: 3)
    alpha = image.extract_band(3)
    low = low_fraction(rgb, weight)
    if low <= MAX_LOW_FOR_SAME
      return removed ? generated(image, :cutout) : Outcome.new(source: 'same', png: nil, reason: :legible)
    end
    return inverted(rgb, alpha, weight, low) if weighted(band_spread(rgb) <= GRAY_CHROMA, weight) >= MIN_GRAY
    return generated(alpha.new_from_image(WHITE).bandjoin(alpha), :silhouette) if one_color?(rgb, weight)

    plate(:several_colors)
  end

  # Preto vira branco e cinza continua cinza: o desenho de dentro da logo é mantido (uma silhueta o apagaria).
  def inverted(rgb, alpha, weight, low_before)
    flipped = rgb.invert
    low = low_fraction(flipped, weight)
    return plate(:mixed_tones) if low > MAX_LOW_AFTER_INVERT || low >= low_before

    generated(flipped.bandjoin(alpha), :inverted)
  end

  def transparent_fraction(image)
    (image.extract_band(3) <= VISIBLE_ALPHA).avg / 255.0
  end

  # Peso de cada pixel nas médias: o alpha dele (0 a 1), e zero para o que é quase invisível.
  def visible_weight(image)
    alpha = image.extract_band(3)
    (alpha > VISIBLE_ALPHA).ifthenelse(alpha, 0).cast(:float) / 255.0
  end

  # Fração (pelo peso) dos pixels em que a condição vale. `mask` é uma imagem 0/255.
  def weighted(mask, weight)
    ((mask.cast(:float) / 255.0) * weight).avg / weight.avg
  end

  # Fração dos pixels visíveis com contraste abaixo de 3:1 sobre o cartão escuro (luminância relativa do WCAG).
  def low_fraction(rgb, weight)
    luminance = rgb.colourspace(:scrgb).recomb(Vips::Image.new_from_array(LUMINANCE_WEIGHTS))
    weighted(luminance < MIN_LUMINANCE, weight)
  end

  # Maior e menor canal de cada pixel: a diferença diz se ele tem cor.
  def band_spread(rgb)
    bands = rgb.bandsplit
    Vips::Image.bandrank(bands, index: 2) - Vips::Image.bandrank(bands, index: 0)
  end

  # Distância de cada pixel a uma cor: a maior diferença entre os três canais.
  def distance_to(rgb, color)
    Vips::Image.bandrank((rgb.cast(:float) - color).abs.bandsplit, index: 2)
  end

  def one_color?(rgb, weight)
    mean = rgb.bandsplit.map { |band| (band.cast(:float) * weight).avg / weight.avg }
    weighted(distance_to(rgb, mean) <= ONE_COLOR_TOLERANCE, weight) >= MIN_ONE_COLOR
  end

  # A mesma imagem com o fundo sólido transparente, ou nil quando não há fundo sólido. Some tudo o que tem a cor do
  # fundo, inclusive o miolo das letras ("o", "a", "e"): no escuro, um miolo que ficasse branco viraria um borrão
  # dentro da letra. (O motor do Studio guarda o miolo; aqui a imagem é feita para fundo escuro, e o certo é furar.)
  def without_solid_background(image)
    rgb = image.extract_band(0, n: 3)
    background = solid_background(rgb)
    return if background.nil?

    distance = distance_to(rgb, background)
    alpha = edge_alpha(image.extract_band(3), distance, distance <= BACKGROUND_TOLERANCE)
    rgb.bandjoin(alpha).copy_memory
  end

  # A cor do fundo ([r, g, b]) quando a imagem tem fundo sólido, ou nil.
  def solid_background(rgb)
    last_x = rgb.width - 1
    last_y = rgb.height - 1
    corners = [[0, 0], [last_x, 0], [0, last_y], [last_x, last_y]].map { |left, top| rgb.getpoint(left, top) }
    base = corners.first
    return unless corners.all? { |corner| corner.zip(base).all? { |value, other| (value - other).abs <= CORNER_TOLERANCE } }

    base if border_match(distance_to(rgb, base) <= BACKGROUND_TOLERANCE) >= MIN_BORDER_MATCH
  end

  # Fração da borda (as quatro faixas de 1 px) que tem a cor do fundo. `near`: 255 onde o pixel parece o fundo.
  def border_match(near)
    strips = [near.crop(0, 0, near.width, 1), near.crop(0, near.height - 1, near.width, 1),
              near.crop(0, 0, 1, near.height), near.crop(near.width - 1, 0, 1, near.height)]
    pixels = strips.sum { |strip| strip.width * strip.height }
    strips.sum { |strip| strip.avg * strip.width * strip.height } / (255.0 * pixels)
  end

  # Alpha novo: zero no fundo (`removed`, 255 onde é fundo); na beirada do desenho (1 px colado ao fundo)
  # proporcional ao quanto o pixel se afasta da cor do fundo, para a borda não ficar serrilhada nem com contorno da
  # cor antiga; o resto fica como estava.
  def edge_alpha(alpha, distance, removed)
    kept = removed.invert
    edge = removed.rank(3, 3, 8) & kept
    body = kept & edge.invert
    reference = body.avg.zero? ? 255.0 : (distance * (body.cast(:float) / 255.0)).avg / (body.avg / 255.0)
    soft = (distance * (255.0 / reference.clamp(48.0, 255.0))).cast(:uchar)
    softened = (soft < alpha).ifthenelse(soft, alpha)
    removed.ifthenelse(0, edge.ifthenelse(softened, alpha)).cast(:uchar)
  end
end
