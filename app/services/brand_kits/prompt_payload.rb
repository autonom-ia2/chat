# O que a IA do e-mail recebe de um kit de marca ou de uma proposta de importação (#1076): dados
# estruturados e compactos — as cores da versão que o e-mail escolheu (clara por padrão, com a cor de texto
# sobre os botões já resolvida pelo contraste), fontes com a pilha de reserva Arial e o link do Google
# Fonts, logo, redes, a linha de identidade do rodapé e o rodapé travado pronto (um só, o canônico).
class BrandKits::PromptPayload
  def initialize(source, mode: BrandKits::EmailPalettes::DEFAULT_MODE, logo_url: nil)
    @source = source
    @mode = BrandKits::EmailPalettes::MODES.include?(mode.to_s) ? mode.to_s : BrandKits::EmailPalettes::DEFAULT_MODE
    @logo_url = logo_url
    @appearance = BrandKits::Appearance.new(kit? ? source.appearance : source['appearance']).to_h
  end

  def to_h
    payload = {
      name: name, mode: @mode, palette: palette, typography: typography, logo_url: logo_url,
      social_links: @appearance['social_links'].map { |link| { network: link['network'], url: link['url'] } },
      footer: @appearance['footer'].slice('company_name', 'address', 'website').compact.symbolize_keys
    }
    payload.merge(footer_mjml: BrandKits::FooterMjml.new(payload).to_s)
  end

  private

  def kit?
    @source.is_a?(BrandKit)
  end

  def name
    kit? ? @source.name : @source['name']
  end

  def palette
    colors = @appearance.dig('palettes', @mode).symbolize_keys
    return colors unless BrandKits::Color.hex?(colors[:primary])

    colors.merge(on_primary: BrandKits::Color.text_on(colors[:primary], ink: colors[:ink]),
                 on_band: BrandKits::Color.readable_ink(colors[:band]))
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
    return @logo_url if @logo_url.present?
    return EmailCampaigns::PublicBlobUrl.call(@source.logo.blob) if kit? && @source.logo.attached?

    @appearance['logo_url']
  end
end
