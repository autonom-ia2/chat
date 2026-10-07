# As duas versões de cores do e-mail a partir das cores do site (#1076). Cada kit guarda as duas e cada
# e-mail escolhe uma:
# - light (padrão, recomendada): fundo branco; o texto é a cor escura do site que passa 4,5:1; os botões
#   são a primary do site se ela aparece no branco (3:1), senão a accent, senão a cor do texto; a faixa do
#   topo (onde fica a logo) é o fundo do site quando ele é escuro, senão o tom claro da primary;
# - dark (igual ao site): o fundo escuro do site, ou um fundo escuro derivado quando o site é claro.
# Detalhes (accent) são decorativos: ficam com a cor do site. Os textos (ink, muted) passam 4,5:1 em todo
# fundo em que a IA os põe (surface, background, tint).
class BrandKits::EmailPalettes
  ROLES = %w[primary accent ink muted surface background tint band].freeze
  MODES = %w[light dark].freeze
  DEFAULT_MODE = 'light'.freeze
  WHITE = BrandKits::Color::WHITE
  DARK_FALLBACK = '#0f172a'.freeze
  DARK_LUMINANCE = BrandKits::PaletteRoles::DARK_LUMINANCE
  NEAR_BLACK_LUMINANCE = 0.05
  NON_TEXT_CONTRAST = 3.0
  MUTED_STEPS = BrandKits::PaletteRoles::MUTED_STEPS
  LIGHT_TINT_ALPHA = 0.12
  DARK_TINT_ALPHA = 0.16
  DARK_SURFACE_LIFT = 0.08

  def self.from_site(site)
    new(site).to_h
  end

  # Branco (texto ou logo branca) some na faixa: contraste abaixo de 3:1.
  def self.light_band?(band)
    BrandKits::Color.contrast(WHITE, band) < NON_TEXT_CONTRAST
  end

  def initialize(site)
    site = site.is_a?(Hash) ? site.stringify_keys : {}
    @site = site.select { |_role, hex| BrandKits::Color.hex?(hex) }.transform_values(&:downcase)
  end

  def to_h
    { 'light' => light, 'dark' => dark }
  end

  private

  def light
    ink = first_readable([@site['ink'], @site['background'], @site['surface']], [WHITE]) || BrandKits::Color::DARK_INK
    primary = first_visible([@site['primary'], @site['accent']], WHITE) || ink
    tint = BrandKits::Color.composite(primary, WHITE, LIGHT_TINT_ALPHA)
    ink = BrandKits::Color::DARK_INK unless readable?(ink, tint)
    {
      'primary' => primary, 'accent' => @site['accent'] || primary, 'ink' => ink,
      'muted' => muted(ink, [WHITE, tint]), 'surface' => WHITE, 'background' => WHITE, 'tint' => tint,
      'band' => site_dark? ? @site['background'] : tint
    }
  end

  def dark
    background, surface = dark_grounds
    ink = first_readable([@site['ink'], WHITE], [surface, background]) || BrandKits::Color.readable_ink(surface)
    primary = first_visible([@site['primary'], @site['accent']], background) || ink
    tint = BrandKits::Color.composite(primary, surface, DARK_TINT_ALPHA)
    {
      'primary' => primary, 'accent' => @site['accent'] || primary, 'ink' => ink,
      'muted' => muted(ink, [surface, background, tint]), 'surface' => surface, 'background' => background, 'tint' => tint,
      'band' => background
    }
  end

  def dark_grounds
    if site_dark?
      background = @site['background']
      surface = @site['surface'] if @site['surface'] && dark?(@site['surface'])
    else
      ink = @site['ink']
      background = ink && BrandKits::Color.luminance(ink) < NEAR_BLACK_LUMINANCE ? ink : DARK_FALLBACK
    end
    [background, surface || BrandKits::Color.composite(WHITE, background, DARK_SURFACE_LIFT)]
  end

  def site_dark?
    @site['background'].present? && dark?(@site['background'])
  end

  def dark?(hex)
    BrandKits::Color.luminance(hex) < DARK_LUMINANCE
  end

  def first_readable(candidates, grounds)
    candidates.compact.find { |hex| grounds.all? { |ground| readable?(hex, ground) } }
  end

  def first_visible(candidates, ground)
    candidates.compact.find { |hex| BrandKits::Color.contrast(hex, ground) >= NON_TEXT_CONTRAST }
  end

  def muted(ink, grounds)
    MUTED_STEPS.lazy.map { |alpha| BrandKits::Color.composite(ink, grounds.first, alpha) }
               .find { |color| grounds.all? { |ground| readable?(color, ground) } } || ink
  end

  def readable?(foreground, background)
    BrandKits::Color.contrast(foreground, background) >= BrandKits::Color::TEXT_CONTRAST
  end
end
