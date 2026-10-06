# O que a IA do e-mail recebe de um kit de marca ou de uma proposta de importação (#1076): dados
# estruturados e compactos — papéis da paleta (com a cor de texto sobre a primary já resolvida pelo
# contraste), fontes com a pilha de reserva Arial e o link do Google Fonts, logo, redes e rodapé.
class BrandKits::PromptPayload
  def initialize(source)
    @source = source
    @appearance = BrandKits::Appearance.new(source.is_a?(BrandKit) ? source.appearance : source['appearance']).to_h
  end

  def to_h
    {
      name: name,
      palette: palette,
      typography: typography,
      logo_url: logo_url,
      social_links: @appearance['social_links'].map { |link| { network: link['network'], url: link['url'] } },
      footer: @appearance['footer'].compact.symbolize_keys
    }
  end

  private

  def name
    @source.is_a?(BrandKit) ? @source.name : @source['name']
  end

  def palette
    colors = @appearance['palette'].symbolize_keys
    return colors unless BrandKits::Color.hex?(colors[:primary])

    colors.merge(on_primary: BrandKits::Color.text_on(colors[:primary], ink: colors[:ink]))
  end

  def typography
    fonts = @appearance['typography']
    fallback = fonts['fallback']
    {
      heading_font: fonts['heading_font'],
      body_font: fonts['body_font'],
      fallback: fallback,
      heading_stack: stack(fonts['heading_font'], fallback),
      body_stack: stack(fonts['body_font'], fallback),
      google_font_url: fonts['google_font_url']
    }.compact
  end

  def stack(family, fallback)
    family ? "'#{family}', #{fallback}" : fallback
  end

  def logo_url
    return Rails.application.routes.url_helpers.rails_blob_url(@source.logo, only_path: false) if @source.is_a?(BrandKit) && @source.logo.attached?

    @appearance['logo_url']
  end
end
