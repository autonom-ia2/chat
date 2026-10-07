# Import by address — the "see it in the browser" page of a sent e-mail (#1099, delivery B). Only https, no user or
# password in it, at most MAX_URL_LENGTH characters; read through SafeFetch with a total deadline, the byte ceiling of
# a pasted model and https required on every redirect hop (SafeFetch's ssrf_filter refuses private addresses on each
# one). The address is the base for the page's relative images. URI and string methods — no regex.
class EmailCampaigns::Import::UrlSource
  TIMEOUT_SECONDS = 15
  MAX_URL_LENGTH = 2048
  SCHEMES = %w[https].freeze
  PAGE_PREFIXES = %w[text/html].freeze
  PAGE_TYPES = %w[application/xhtml+xml].freeze
  ERRORS = {
    SafeFetch::UnsafeUrlError => :url_unsafe,
    SafeFetch::InvalidUrlError => :url_not_https,
    SafeFetch::FileTooLargeError => :too_large,
    SafeFetch::UnsupportedContentTypeError => :url_not_html,
    SafeFetch::Error => :url_unreachable
  }.freeze

  Page = Data.define(:markup, :base_url)

  # The address as given, or an error code for the screen: :url_invalid or :url_not_https.
  def self.check!(url)
    text = url.to_s.strip
    raise EmailCampaigns::Import::Error, :url_invalid if text.empty? || text.length > MAX_URL_LENGTH

    check_parts!(URI.parse(text))
    text
  rescue URI::InvalidURIError
    raise EmailCampaigns::Import::Error, :url_invalid
  end

  def self.check_parts!(uri)
    raise EmailCampaigns::Import::Error, :url_not_https unless SCHEMES.include?(uri.scheme&.downcase)
    raise EmailCampaigns::Import::Error, :url_invalid if uri.host.blank? || uri.userinfo.present?
  end

  def self.call(url, deadline: EmailCampaigns::Import::Deadline.new(TIMEOUT_SECONDS))
    new(check!(url), deadline).call
  end

  def initialize(url, deadline)
    @url = url
    @deadline = deadline
  end

  def call
    seconds = [TIMEOUT_SECONDS, @deadline.remaining].min
    raise EmailCampaigns::Import::Error, :too_slow unless seconds.positive?

    markup = SafeFetch.fetch(@url, max_bytes: EmailCampaigns::Import::Limits::MAX_BYTES, total_timeout: seconds, schemes: SCHEMES,
                                   allowed_content_type_prefixes: PAGE_PREFIXES, allowed_content_types: PAGE_TYPES) do |result|
      result.tempfile.read
    end
    Page.new(markup: markup.to_s, base_url: @url)
  rescue SafeFetch::Error => e
    raise EmailCampaigns::Import::Error, ERRORS.find { |klass, _code| e.is_a?(klass) }.last
  end
end
