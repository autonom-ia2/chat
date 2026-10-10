# Candidatas de cor de uma página (#1076). Junta, com peso e origem:
# - fundo e texto do <body>/:root (papéis background e ink);
# - fundo dos botões e links com cara de botão (a cor de ação da marca);
# - variáveis CSS com nome de marca (primary/brand → principal; accent/secondary → destaque);
# - <meta name="theme-color">;
# - frequência das cores saturadas aplicadas aos elementos da página.
# Cinzas (branco, preto, grafite) não entram como cor de marca.
class BrandKits::Extraction::Colors
  Candidate = Struct.new(:hex, :score, :source, :confidence)

  PRIMARY_VARIABLE_HINTS = %w[primary brand].freeze
  ACCENT_VARIABLE_HINTS = %w[accent secondary highlight].freeze
  MAX_ELEMENTS = 4000
  WEIGHTS = { primary_variable: 6, theme_color: 4, accent_variable: 5, button_rule: 2, button: 3, element: 1 }.freeze

  def initialize(document, stylesheets)
    @document = document
    @index = stylesheets
  end

  def background
    root_color(%w[background-color background], 'background')
  end

  def ink
    root_color(%w[color], 'foreground')
  end

  # Cores de ação: fundo de botões e de links com fundo próprio, mais regras .btn/.button.
  def buttons
    tally = Hash.new(0)
    @document.css('button, a, input[type="submit"]').first(MAX_ELEMENTS).each do |node|
      hex = background_of(@index.style_for(node))
      tally[hex] += 1 if brand_color?(hex)
    end
    @index.button_rules.each do |values|
      hex = background_of(values.transform_values { |value| @index.resolve(value) })
      tally[hex] += WEIGHTS[:button_rule] if brand_color?(hex)
    end
    ranked(tally, 'button_background', 'medium')
  end

  # Todas as cores de marca da página, ranqueadas por peso.
  def brand
    candidates = variable_candidates + theme_color_candidates + element_candidates
    merged = candidates.group_by(&:hex).map do |hex, group|
      best = group.max_by(&:score)
      Candidate.new(hex, group.sum(&:score), best.source, best.confidence)
    end
    merged.sort_by { |candidate| [-candidate.score, -BrandKits::Color.chroma(candidate.hex)] }
  end

  def accent_variables
    variable_candidates.select { |candidate| candidate.source == 'css_variable_accent' }
  end

  private

  def root_color(properties, variable)
    hex = root_styles.lazy.map { |style| properties.lazy.map { |property| color_in(style[property]) }.find(&:itself) }.find(&:itself)
    return Candidate.new(hex, 1, 'body_style', 'medium') if hex

    hex = BrandKits::Color.parse(@index.variables["--#{variable}"])
    hex ? Candidate.new(hex, 1, 'css_variable', 'medium') : nil
  end

  # Estilo do <body> (regra + classes + inline), depois as regras de html e :root.
  def root_styles
    body_node = @document.at_css('body')
    body = @index.root_style('body')
    body = body.merge(@index.style_for(body_node)) if body_node
    [body, @index.root_style('html'), @index.root_style('root')]
  end

  def variable_candidates
    @variable_candidates ||= @index.variables.filter_map do |name, value|
      hex = BrandKits::Color.parse(value)
      variable_candidate(name.downcase, hex) if brand_color?(hex)
    end
  end

  def variable_candidate(name, hex)
    if ACCENT_VARIABLE_HINTS.any? { |hint| name.include?(hint) }
      Candidate.new(hex, WEIGHTS[:accent_variable], 'css_variable_accent', 'high')
    elsif PRIMARY_VARIABLE_HINTS.any? { |hint| name.include?(hint) }
      Candidate.new(hex, WEIGHTS[:primary_variable], 'css_variable_primary', 'high')
    end
  end

  def theme_color_candidates
    hex = BrandKits::Color.parse(@document.at_css('meta[name="theme-color"]')&.[]('content'))
    brand_color?(hex) ? [Candidate.new(hex, WEIGHTS[:theme_color], 'theme_color', 'high')] : []
  end

  def element_candidates
    tally = Hash.new(0)
    @document.css('body *').first(MAX_ELEMENTS).each do |node|
      style = @index.style_for(node)
      [background_of(style), color_in(style['color'])].each { |hex| tally[hex] += WEIGHTS[:element] if brand_color?(hex) }
    end
    ranked(tally, 'page_frequency', 'medium')
  end

  def ranked(tally, source, confidence)
    tally.map { |hex, score| Candidate.new(hex, score, source, confidence) }
         .sort_by { |candidate| [-candidate.score, -BrandKits::Color.chroma(candidate.hex)] }
  end

  def background_of(style)
    color_in(style['background-color']) || color_in(style['background'])
  end

  # Primeira cor sólida de um valor (o atalho `background` pode trazer url(), posição etc.).
  def color_in(value)
    return nil if value.blank?

    direct = BrandKits::Color.parse(value)
    return direct if direct

    value.split.lazy.map { |token| BrandKits::Color.parse(token) }.find(&:itself)
  end

  def brand_color?(hex)
    hex.present? && !BrandKits::Color.neutral?(hex)
  end
end
