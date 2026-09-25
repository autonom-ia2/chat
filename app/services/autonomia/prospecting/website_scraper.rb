# Extrai contatos da página do site do lead. O download é do SafePageFetcher, que passa todo destino pela
# UrlGuard e conecta no IP checado (#476).
class Autonomia::Prospecting::WebsiteScraper
  MAX_BODY_BYTES = Autonomia::Prospecting::SafePageFetcher::MAX_BODY_BYTES
  USER_AGENT = Autonomia::Prospecting::SafePageFetcher::USER_AGENT
  FetchFailed = Autonomia::Prospecting::SafePageFetcher::FetchFailed
  BlockedUrl = Autonomia::Agents::Knowledge::UrlGuard::BlockedUrl
  NETWORK_ERRORS = [
    SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error
  ].freeze

  Result = Struct.new(:data, keyword_init: true)

  def initialize(url:, resolver: Autonomia::Prospecting::SafePageFetcher::DEFAULT_RESOLVER)
    @url = url.to_s.strip
    @resolver = resolver
  end

  def perform
    return Result.new(data: empty_payload('missing_website')) if @url.blank?

    parse_html(Autonomia::Prospecting::SafePageFetcher.new(resolver: @resolver).fetch(normalized_uri))
  rescue FetchFailed => e
    Result.new(data: empty_payload(e.code))
  rescue BlockedUrl => e
    Result.new(data: empty_payload('blocked_url', e.message))
  rescue URI::InvalidURIError
    Result.new(data: empty_payload('invalid_url'))
  rescue Net::OpenTimeout, Net::ReadTimeout
    Result.new(data: empty_payload('timeout'))
  rescue *NETWORK_ERRORS => e
    Result.new(data: empty_payload('connection_failed', e.message.to_s.truncate(160)))
  end

  private

  def normalized_uri
    raw = @url.downcase.start_with?('http://', 'https://') ? @url : "https://#{@url}"
    URI.parse(raw)
  end

  def parse_html(page)
    doc = Nokogiri::HTML(page.body, nil, page_encoding(page))
    text = normalized_text(doc)
    links = normalized_links(doc, page.uri)
    return Result.new(data: empty_payload('empty_page')) if text.blank? && links.empty? && title_for(doc).blank?

    Result.new(data: page_data(doc, text, links, page))
  end

  def page_data(doc, text, links, page)
    {
      'website' => page.uri.to_s,
      'title' => title_for(doc),
      'description' => meta_content(doc, 'description'),
      'email' => extract_email(text, links),
      'phone' => extract_phone(text),
      'whatsapp' => extract_whatsapp(text, links),
      'instagram' => social_link(links, 'instagram.com'),
      'facebook' => social_link(links, 'facebook.com'),
      'linkedin' => linkedin_link(links),
      'cnpj' => extract_cnpj(text),
      'source_urls' => links.first(20),
      'text_excerpt' => text.first(3000),
      'truncated' => (true if page.truncated),
      'scraped_at' => Time.current.iso8601
    }.compact
  end

  # Charset do cabeçalho; sem ele, o da própria página (meta); sem os dois, UTF-8.
  def page_encoding(page)
    page.charset.presence || Nokogiri::HTML4::EncodingReader.detect_encoding(page.body) || 'UTF-8'
  end

  def normalized_text(doc)
    doc.css('script, style, noscript, svg').remove
    doc.text.to_s.gsub(/\s+/, ' ').strip
  end

  def normalized_links(doc, uri)
    doc.css('a[href], link[href]').filter_map do |node|
      href = node['href'].to_s.strip
      next if href.blank?

      URI.join(uri, href).to_s
    rescue URI::InvalidURIError
      nil
    end.uniq
  end

  def title_for(doc)
    doc.at_css('meta[property="og:title"]')&.[]('content').presence ||
      doc.at_css('title')&.text.to_s.strip.presence
  end

  def meta_content(doc, name)
    doc.at_css("meta[name=\"#{name}\"]")&.[]('content').presence ||
      doc.at_css("meta[property=\"og:#{name}\"]")&.[]('content').presence
  end

  def extract_email(text, links)
    mailto = links.find { |link| link.start_with?('mailto:') }
    return mailto.delete_prefix('mailto:').split('?').first if mailto.present?

    text.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i)&.[](0)
  end

  def extract_phone(text)
    match = text.match(/\(?\d{2}\)?\s?\d{4,5}[-\s]?\d{4}/)
    return if match.blank?

    digits = match[0].gsub(/\D/, '')
    return unless digits.length.between?(10, 11)

    "+55#{digits}"
  end

  def extract_whatsapp(text, links)
    link = links.find { |item| item.match?(%r{(?:wa\.me|api\.whatsapp\.com)}i) }
    digits = link.to_s.match(/(?:phone=|wa\.me\/)(\+?\d{10,15})/i)&.[](1)
    return "+#{digits.gsub(/\D/, '')}" if digits.present?

    extract_phone(text) if text.match?(/whatsapp|zap/i)
  end

  def social_link(links, domain)
    links.find do |link|
      host = URI.parse(link).host.to_s.delete_prefix('www.')
      host == domain && !link.match?(%r{/share|/sharer|/intent}i)
    rescue URI::InvalidURIError
      false
    end
  end

  def linkedin_link(links)
    links.find do |link|
      uri = URI.parse(link)
      host = uri.host.to_s.delete_prefix('www.')
      host == 'linkedin.com' && uri.path.match?(%r{\A/(in|company)/}i)
    rescue URI::InvalidURIError
      false
    end
  end

  def extract_cnpj(text)
    text.match(/\b\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}\b/)&.[](0)
  end

  def empty_payload(error, message = nil)
    {
      'error' => error,
      'message' => message,
      'scraped_at' => Time.current.iso8601
    }.compact
  end
end
