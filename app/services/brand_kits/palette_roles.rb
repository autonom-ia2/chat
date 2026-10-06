# Papéis da paleta a partir das cores encontradas (#1076), portado de `proposals.ts` do Bio com as regras
# de contraste do WCAG:
# - background: fundo do <body> (ou branco); surface: branco, ou o fundo clareado 8% quando ele é escuro;
# - ink: cor do texto do <body> se passa 4,5:1 no fundo e na superfície, senão a tinta legível;
# - primary: cor de ação (fundo dos botões), senão a cor de marca mais forte, desde que passe 3:1 no fundo;
# - accent: a próxima cor de marca de outra matiz (≥ 30°), diferente do fundo e da tinta; senão a primary;
# - muted: a tinta misturada na superfície até onde ainda passa 4,5:1; tint: a primary a 12% na superfície.
class BrandKits::PaletteRoles
  DEFAULT_BACKGROUND = BrandKits::Color::WHITE
  DARK_LUMINANCE = 0.35
  NON_TEXT_CONTRAST = 3.0
  MIN_HUE_DISTANCE = 30
  MUTED_STEPS = [0.7, 0.8, 0.9, 1.0].freeze
  TINT_ALPHA = 0.12

  attr_reader :palette, :fields, :warnings

  # background/ink: Candidate ou nil; buttons/brand: listas ranqueadas de Candidate (hex, score, source, confidence).
  def initialize(background:, ink:, buttons:, brand:, accent_hints: [])
    @background_candidate = background
    @ink_candidate = ink
    @buttons = buttons
    @brand = brand
    @accent_hints = accent_hints
    @fields = {}
    @warnings = []
    @palette = build
  end

  private

  def build
    background = pick_background
    surface = BrandKits::Color.luminance(background) < DARK_LUMINANCE ? BrandKits::Color.composite('#ffffff', background, 0.08) : '#ffffff'
    ink = pick_ink(background, surface)
    primary = pick_primary(background, ink)
    {
      'primary' => primary,
      'accent' => pick_accent(primary, background, ink),
      'ink' => ink,
      'muted' => muted(ink, surface),
      'surface' => surface,
      'background' => background,
      'tint' => BrandKits::Color.composite(primary, surface, TINT_ALPHA)
    }
  end

  def pick_background
    return record('background', @background_candidate) if @background_candidate

    @fields['palette.background'] = { 'source' => 'default', 'confidence' => 'low' }
    DEFAULT_BACKGROUND
  end

  def pick_ink(background, surface)
    candidate = @ink_candidate
    return record('ink', candidate) if candidate && readable?(candidate.hex, background) && readable?(candidate.hex, surface)

    @warnings << 'ink_adjusted_for_contrast' if candidate
    @fields['palette.ink'] = { 'source' => 'contrast_rule', 'confidence' => 'medium' }
    ink = BrandKits::Color.readable_ink(surface)
    readable?(ink, background) ? ink : BrandKits::Color.readable_ink(background)
  end

  def pick_primary(background, ink)
    pool = @buttons + @brand
    @warnings << 'colors_not_found' if pool.empty?
    chosen = pool.find { |candidate| BrandKits::Color.contrast(candidate.hex, background) >= NON_TEXT_CONTRAST }
    return record('primary', chosen) if chosen

    @warnings << 'primary_adjusted_for_contrast' if pool.any?
    @fields['palette.primary'] = { 'source' => 'ink', 'confidence' => 'low' }
    ink
  end

  def pick_accent(primary, background, ink)
    pool = @accent_hints + @brand
    chosen = pool.find do |candidate|
      [primary, background, ink].exclude?(candidate.hex) &&
        (BrandKits::Color.neutral?(primary) || BrandKits::Color.hue_distance(candidate.hex, primary) >= MIN_HUE_DISTANCE)
    end
    return record('accent', chosen) if chosen

    @fields['palette.accent'] = { 'source' => 'primary', 'confidence' => 'low' }
    primary
  end

  def muted(ink, surface)
    @fields['palette.muted'] = { 'source' => 'derived', 'confidence' => 'medium' }
    MUTED_STEPS.lazy.map { |alpha| BrandKits::Color.composite(ink, surface, alpha) }.find { |color| readable?(color, surface) } || ink
  end

  def readable?(foreground, background)
    BrandKits::Color.contrast(foreground, background) >= BrandKits::Color::TEXT_CONTRAST
  end

  def record(role, candidate)
    @fields["palette.#{role}"] = { 'source' => candidate.source, 'confidence' => candidate.confidence }
    candidate.hex
  end
end
