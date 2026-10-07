# Lê a identidade visual de um site e devolve uma PROPOSTA (não grava nada) — #1076.
#
# Busca, sempre pelo SafeFetch (SSRF: IP privado, localhost e metadados recusados a cada salto):
# a página (até 2 MB) e até 6 folhas de estilo do mesmo site (até 1 MB cada), tudo num prazo total de 20 s.
# Folha de terceiro não é buscada; a do Google Fonts só vira link. A extração fica em BrandKits::Proposal.
# A logo NÃO é baixada aqui: só quando a pessoa salva o kit (BrandKits::LogoDownloader).
class BrandKits::SiteImporter
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  PAGE_MAX_BYTES = 2.megabytes
  STYLESHEET_MAX_BYTES = 1.megabyte
  INLINE_STYLE_MAX_BYTES = 1.megabyte
  MAX_STYLESHEETS = 6
  TOTAL_DEADLINE = 20
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  MAX_REDIRECTS = 3
  HTML_TYPES = %w[text/html application/xhtml+xml].freeze
  CSS_TYPES = %w[text/css text/plain].freeze
  USER_AGENT = 'Mozilla/5.0 (compatible; Chat2YouBrandImport/1.0)'.freeze

  def self.normalize_url(value)
    text = value.to_s.strip
    text = "https://#{text}" unless text.include?('://') || text.empty?
    uri = BrandKits::WebAddress.parse(text)
    raise Error, 'invalid_url' if uri.nil? || uri.port != uri.default_port

    uri.path = '/' if uri.path.empty?
    uri.fragment = nil
    uri.to_s
  end

  def initialize(url)
    @url = self.class.normalize_url(url)
    @page_uri = URI.parse(@url)
    @warnings = []
    @requests = 0
    @bytes = 0
  end

  def perform
    @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    document = Nokogiri::HTML(fetch_page)
    css = stylesheets(document)
    google_font_links = BrandKits::Extraction::GoogleFontLinks.new(document, css, @page_uri).perform
    proposal = BrandKits::Proposal.new(document, BrandKits::Extraction::StylesheetIndex.new(css),
                                       page_uri: @page_uri, google_font_links: google_font_links, warnings: @warnings)
    proposal.to_h.merge('metrics' => { 'requests' => @requests, 'bytes' => @bytes })
  end

  private

  def fetch_page
    fetch(@url, max_bytes: PAGE_MAX_BYTES, types: HTML_TYPES)
  rescue SafeFetch::Error => e
    raise Error, fetch_error_code(e)
  end

  def fetch(url, max_bytes:, types:)
    remaining = TOTAL_DEADLINE - elapsed
    raise SafeFetch::TotalTimeoutError, 'deadline' if remaining <= 0

    @requests += 1
    body = SafeFetch.fetch(url, max_bytes: max_bytes, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT,
                                total_timeout: remaining, max_redirects: MAX_REDIRECTS, headers: { 'User-Agent' => USER_AGENT },
                                allowed_content_type_prefixes: [], allowed_content_types: types) { |result| result.tempfile.read }
    @bytes += body.bytesize
    body.force_encoding(Encoding::UTF_8).scrub
  end

  def fetch_error_code(error)
    case error
    when SafeFetch::InvalidUrlError then 'invalid_url'
    when SafeFetch::UnsafeUrlError then 'unsafe_url'
    when SafeFetch::HttpError then 'http_error'
    when SafeFetch::FileTooLargeError then 'page_too_large'
    when SafeFetch::UnsupportedContentTypeError then 'not_html'
    when SafeFetch::TotalTimeoutError then 'timeout'
    else 'fetch_failed'
    end
  end

  # Folhas do mesmo site (até MAX_STYLESHEETS) e os <style> da página.
  def stylesheets(document)
    inline = document.css('style').map(&:content).join("\n").byteslice(0, INLINE_STYLE_MAX_BYTES).to_s.scrub
    linked = stylesheet_urls(document)
    @warnings << 'stylesheet_limit_reached' if linked.size > MAX_STYLESHEETS
    linked.first(MAX_STYLESHEETS).filter_map { |url| fetch_stylesheet(url) } + [inline]
  end

  def stylesheet_urls(document)
    document.css('link[href]').filter_map do |node|
      next unless node['rel'].to_s.downcase.split.include?('stylesheet')

      uri = BrandKits::WebAddress.parse(BrandKits::WebAddress.join(@page_uri, node['href']))
      uri.to_s if uri && BrandKits::WebAddress.same_site?(uri, @page_uri)
    end.uniq
  end

  def fetch_stylesheet(url)
    fetch(url, max_bytes: STYLESHEET_MAX_BYTES, types: CSS_TYPES)
  rescue SafeFetch::Error
    @warnings << 'stylesheet_failed'
    nil
  end

  def elapsed
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started
  end
end
