# Links and images of an imported model (#1099). Links keep only http, https, mailto and tel (a removed link keeps
# its text); a click redirect — an address whose path is a click-tracking one (/track/click, /mk/cl/, /r/...) — is
# unwrapped only when its destination parameter is an absolute http(s) address on another host — UTM parameters
# carried over — and is otherwise kept as it is, with a warning; it is never followed over the network. Any other link
# with a destination-like parameter (a share button's ?u=, a login's ?redirect=) is a page of its own and stays as is.
# Tracking parameters of the source platform leave. Images keep http(s) and raster data: addresses (both listed for
# copying later); anything else becomes a placeholder to swap. Relative addresses resolve only against the page address
# of an import by URL. URI, Rack::Utils and string methods — no regex.
class EmailCampaigns::Import::LinkPolicy
  REDIRECT_PARAMS = %w[u url redirect redirect_url redirect_uri target dest destination link].freeze
  # Path segments of the click-tracking addresses e-mail platforms wrap links in. A URL's structure, not a person's text.
  REDIRECT_SEGMENTS = %w[c cl click clicks ct l link links ls mk out r redir redirect t track tracking wf].freeze
  TRACKING_PARAMS = %w[_hsenc _hsmi mc_cid mc_eid].freeze
  KEPT_SCHEMES = %w[mailto tel].freeze
  IMAGE_TYPES = %w[image/png image/jpeg image/jpg image/gif image/webp].freeze
  UNSUBSCRIBE = '{{ unsubscribe_url }}'.freeze

  def initialize(report, base_url: nil)
    @report = report
    @base_url = base_url
  end

  def call(root)
    root.css('a').each { |link| link_node(link) }
    root.css('img').each { |image| image_node(image) }
    root
  end

  # A clean href, or nil when the link must go (the reason is already recorded).
  def href(value)
    text = value.to_s.strip
    return text if text.split.join == UNSUBSCRIBE.split.join
    return refuse(text, :placeholder_link) if text.start_with?('{{')

    text = absolute(text)
    scheme = EmailCampaigns::Import::Url.scheme(text)
    return text if KEPT_SCHEMES.include?(scheme)
    return refuse(text, scheme.nil? ? :relative : :unsafe) unless EmailCampaigns::Import::Url::HTTP.include?(scheme)

    strip_tracking(unwrap_redirect(EmailCampaigns::Import::Url.clean(text)))
  end

  # [src, kind] with kind :remote or :data, or [nil, :missing], recorded under `missing`: the blocking code by default,
  # a softer one for an image that has a fallback (the default icon of a social link).
  def image(value, missing: :image_missing)
    text = absolute(value.to_s.strip)
    return [EmailCampaigns::Import::Url.clean(text), :remote] if EmailCampaigns::Import::Url.http?(text)
    return [text, :data] if raster_data?(text)

    @report.add(missing)
    @report.drop_image(text, :missing) if text.present?
    [nil, :missing]
  end

  private

  def link_node(link)
    return unwrap(link) if link['href'].nil?

    clean = href(link['href'])
    clean ? link['href'] = clean : unwrap(link)
  end

  def image_node(image)
    return if image['data-import-missing']

    src, kind = image(image['src'])
    return image['src'] = src unless kind == :missing

    image.remove_attribute('src')
    image['data-import-missing'] = '1'
  end

  def refuse(text, reason)
    @report.add(:link_removed, item: reason.to_s)
    @report.drop_link(text, reason)
    nil
  end

  def unwrap(link)
    link.children.to_a.each { |child| link.add_previous_sibling(child) }
    link.remove
  end

  def absolute(value)
    return "https:#{EmailCampaigns::Import::Url.clean(value)}" if EmailCampaigns::Import::Url.protocol_relative?(value)
    return value if @base_url.nil? || value.empty? || EmailCampaigns::Import::Url.scheme(value) || value.start_with?('#', '{{')

    EmailCampaigns::Import::Url.resolve(value, @base_url) || value
  end

  def raster_data?(text)
    return false unless text.downcase.start_with?('data:')

    header = text[5...(text.index(',') || 5)].to_s.downcase
    IMAGE_TYPES.include?(header.split(';').first) && header.split(';').include?('base64')
  end

  def unwrap_redirect(href)
    uri = URI.parse(href)
    return href unless redirect_path?(uri.path)

    params = Rack::Utils.parse_query(uri.query.to_s)
    keys = params.keys.select { |key| REDIRECT_PARAMS.include?(key.downcase) }
    return href if keys.empty?
    return kept_redirect(href) unless keys.one? && trusted?(params[keys.first], uri)

    unwrapped(href, carry_utm(params[keys.first], params))
  rescue URI::InvalidURIError
    href
  end

  def unwrapped(href, final)
    @report.rewrite_link(href, final)
    @report.add(:link_unwrapped)
    final
  end

  def redirect_path?(path)
    path.to_s.downcase.split('/').any? { |segment| REDIRECT_SEGMENTS.include?(segment) }
  end

  def kept_redirect(href)
    @report.add(:redirect_kept)
    href
  end

  def trusted?(destination, uri)
    return false unless destination.is_a?(String)

    target = URI.parse(destination)
    EmailCampaigns::Import::Url::HTTP.include?(target.scheme) && target.host.present? && target.host != uri.host
  rescue URI::InvalidURIError
    false
  end

  def carry_utm(destination, params)
    present = Rack::Utils.parse_query(URI.parse(destination).query.to_s).keys
    utm = params.select { |key, value| key.start_with?('utm_') && value.is_a?(String) && present.exclude?(key) }
    return destination if utm.empty?

    "#{destination}#{destination.include?('?') ? '&' : '?'}#{Rack::Utils.build_query(utm)}"
  end

  def strip_tracking(href)
    base, query = href.split('?', 2)
    return href if query.nil?

    query, fragment = query.split('#', 2)
    pairs = query.split('&')
    kept = pairs.reject { |pair| TRACKING_PARAMS.include?(pair.split('=', 2).first.to_s.downcase) }
    return href if kept.size == pairs.size

    @report.add(:tracking_removed)
    out = kept.empty? ? base : "#{base}?#{kept.join('&')}"
    fragment ? "#{out}##{fragment}" : out
  end
end
