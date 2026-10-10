# Links do Google Fonts de uma página (#1076): <link href> e @import nas folhas já baixadas. A folha do
# Google não é buscada — o link vai para o e-mail (`mj-font`) como está.
class BrandKits::Extraction::GoogleFontLinks
  HOSTS = %w[fonts.googleapis.com].freeze
  MAX_IMPORTS = 20
  URL_END_CHARS = ['"', "'", ' ', "\n", "\t", ')'].freeze

  def initialize(document, css_texts, page_uri)
    @document = document
    @css_texts = css_texts
    @page_uri = page_uri
  end

  # [{ url:, source: 'link' | 'import' }], sem repetir endereço.
  def perform
    links = @document.css('link[href]').filter_map { |node| font_url(node['href']) }.map { |url| { url: url, source: 'link' } }
    imports = @css_texts.flat_map { |css| imports(css) }.filter_map { |url| font_url(url) }.map { |url| { url: url, source: 'import' } }
    (links + imports).uniq { |link| link[:url] }
  end

  private

  def font_url(value)
    url = BrandKits::WebAddress.join(@page_uri, value)
    uri = url && URI.parse(url)
    return nil unless uri && HOSTS.include?(uri.host.downcase)

    uri.scheme = 'https'
    uri.to_s
  rescue URI::Error
    nil
  end

  # Endereços dos @import de uma folha: `@import url("x")`, `@import url(x)` ou `@import "x"`.
  def imports(css)
    css.to_s.split('@import').drop(1).first(MAX_IMPORTS).filter_map do |chunk|
      statement = chunk.split(';', 2).first.to_s.strip
      statement = statement.delete_prefix('url(').split(')', 2).first.to_s if statement.start_with?('url(')
      statement.strip.delete_prefix('"').delete_prefix("'").each_char.take_while { |char| URL_END_CHARS.exclude?(char) }.join.presence
    end
  end
end
