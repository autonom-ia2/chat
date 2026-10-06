# Rodapé travado do e-mail montado pelo sistema a partir do kit (#1076): linha de redes, empresa, endereço,
# telefone/site e o link {{ unsubscribe_url }}. Todo valor do kit é escapado; nenhuma tag se fecha sozinha.
# MJML não tem ícone para TikTok e WhatsApp: esses usam o ícone genérico "web" com o nome escrito.
class BrandKits::FooterMjml
  MJML_ICON_NETWORKS = %w[facebook instagram linkedin youtube x].freeze
  NETWORK_LABELS = { 'tiktok' => 'TikTok', 'whatsapp' => 'WhatsApp' }.freeze

  def initialize(source, locale: I18n.locale)
    @payload = BrandKits::PromptPayload.new(source).to_h
    @locale = locale
  end

  def to_s
    palette = @payload[:palette]
    <<~MJML.strip
      <mj-section css-class="footer-locked" background-color="#{escape(palette[:surface])}" padding="24px 16px">
        <mj-column>
      #{[social_row, text_block].compact.join("\n")}
        </mj-column>
      </mj-section>
    MJML
  end

  private

  def social_row
    links = @payload[:social_links]
    return nil if links.empty?

    elements = links.map { |link| social_element(link) }.join("\n")
    %(    <mj-social font-size="12px" icon-size="24px" mode="horizontal" align="center" padding="0 0 12px">\n#{elements}\n    </mj-social>)
  end

  def social_element(link)
    href = escape(link[:url])
    if MJML_ICON_NETWORKS.include?(link[:network])
      %(      <mj-social-element name="#{link[:network]}" href="#{href}"></mj-social-element>)
    else
      %(      <mj-social-element name="web" href="#{href}">#{escape(NETWORK_LABELS[link[:network]])}</mj-social-element>)
    end
  end

  def text_block
    lines = (kit_lines + [I18n.t('brand_kits.footer.reason', locale: @locale)]).map { |line| paragraph(escape(line)) }
    lines << paragraph(unsubscribe_link)
    %(    <mj-text font-family="#{font_attribute}" font-size="12px" color="#{escape(muted)}" ) +
      %(align="center" line-height="1.6">\n#{lines.join("\n")}\n    </mj-text>)
  end

  def kit_lines
    footer = @payload[:footer]
    contact = [footer[:phone], website_label(footer[:website])].compact.join(' · ').presence
    [footer[:company_name], footer[:address], contact].compact
  end

  def unsubscribe_link
    label = escape(I18n.t('brand_kits.footer.unsubscribe', locale: @locale))
    %(<a href="{{ unsubscribe_url }}" style="color:#{escape(muted)};text-decoration:underline;">#{label}</a>)
  end

  def paragraph(html)
    %(      <p style="margin:0;">#{html}</p>)
  end

  def website_label(url)
    url && URI.parse(url).host
  rescue URI::Error
    nil
  end

  # O nome da fonte vai entre aspas simples dentro do atributo de aspas duplas; o resto é escapado.
  def font_attribute
    escape(@payload[:typography][:body_stack]).gsub('&#39;', "'")
  end

  def muted
    @payload[:palette][:muted]
  end

  def escape(value)
    ERB::Util.html_escape(value.to_s)
  end
end
