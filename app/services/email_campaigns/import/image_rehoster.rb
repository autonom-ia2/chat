# Copies the images of an imported design to the installation (#1099, delivery B) and points the MJML at them. Each
# image comes from one place only: the .zip that was sent (by its relative name), a data: address (decoded within
# MAX_SOURCE_BYTES, checked before decoding) or the internet — over https only: an http address is tried as https and
# never falls back to http, and every redirect hop must stay on https (SafeFetch `schemes:`), with a byte ceiling and a
# total deadline per download inside a global budget of BUDGET_SECONDS and MAX_IMAGES. The type is read from the bytes
# (Marcel): PNG, JPEG, GIF or WebP; SVG and anything else are refused. ImageCompressor makes it fit, and the copy is
# served at a permanent public address (PublicUrl). The custom icons of social links are copied the same way. An image
# that fails becomes the "image to swap" placeholder with a blocking warning (an image block), leaves the section
# background marking the section (MISSING_BACKGROUND_CLASS, same warning, seen by SaveCheck), or leaves a social link
# with its network's default icon (a warning). Report entries keep the outcome; data: addresses are shortened and archive
# images named by their relative path. `rehost` also answers where each source went (`copies`, for the preview of the
# original) and calls `on_copy` after each image (done, total), for the screen to tell how far the copying is.
class EmailCampaigns::Import::ImageRehoster
  MAX_IMAGES = 40
  BUDGET_SECONDS = 30
  FETCH_SECONDS = 10
  MAX_SOURCE_BYTES = 5 * 1024 * 1024
  RASTER_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  SCHEMES = %w[https].freeze
  DATA_PREFIX = 'data:'.freeze
  BASE64_MARK = ';base64'.freeze
  REPORT_SRC_LIMIT = 60
  BACKGROUND_ATTRIBUTES = %w[background-url background-size background-repeat].freeze

  Failure = Class.new(StandardError)
  Result = Data.define(:mjml, :copies)

  def self.call(mjml, report, import:, files: {}, deadline: EmailCampaigns::Import::Deadline.new(BUDGET_SECONDS))
    rehost(mjml, report, import: import, files: files, deadline: deadline).mjml
  end

  # Result with the MJML and { source => public address } of every image that was copied. Options: files:, deadline:,
  # on_copy:.
  def self.rehost(mjml, report, import:, **options)
    deadline = options[:deadline] || EmailCampaigns::Import::Deadline.new(BUDGET_SECONDS)
    new(report, import, options[:files] || {}, deadline, options[:on_copy]).rehost(mjml)
  end

  # Every image address of an MJML design (image blocks, social icons and section backgrounds), placeholders aside.
  def self.sources(mjml)
    found = []
    EmailCampaigns::MjmlCanonicalizer.call(mjml.to_s) do |root, _cut|
      found.concat(image_nodes(root).map { |node| node['src'] }, background_nodes(root).map { |node| node['background-url'] })
      {}
    end
    found.compact.uniq.reject { |src| src.start_with?('/') && !src.start_with?('//') }
  end

  def self.image_nodes(root)
    root.css('mj-image, mj-social-element').select { |node| node['src'].present? }
  end

  def self.background_nodes(root)
    root.css('[background-url]').select { |node| node['background-url'].present? }
  end

  def initialize(report, import, files, deadline, on_copy = nil)
    @report = report
    @import = import
    @files = files
    @deadline = deadline.slice(BUDGET_SECONDS)
    @on_copy = on_copy
  end

  def rehost(mjml)
    EmailCampaigns::Import::PublicUrl.frontend
    entries = Array(@report.images).map { |image| image.to_h.symbolize_keys }
    copies = entries.each_with_index.to_h { |entry, index| [entry[:src], copied(entry[:src], index, entries.size)] }
    @report.images = entries.map { |entry| describe(entry, copies[entry[:src]]) }
    settle_report(copies.values)
    Result.new(mjml: point(mjml, copies), copies: addresses(copies))
  end

  private

  def addresses(copies)
    copies.filter_map { |src, copy| [src, copy[:url]] if copy[:url] }.to_h
  end

  def copied(src, index, total)
    copy(src, index).tap { @on_copy&.call(index + 1, total) }
  end

  def copy(src, index)
    raise Failure, 'too_many' if index >= MAX_IMAGES
    raise Failure, 'out_of_time' unless @deadline.remaining.positive?

    bytes = read(src)
    type = Marcel::MimeType.for(StringIO.new(bytes)).to_s
    raise Failure, 'unsupported_type' unless RASTER_TYPES.include?(type)

    output = EmailCampaigns::Import::ImageCompressor.call(bytes, type)
    { url: upload(output, index), compressed: output.compressed, animation_lost: output.animation_lost }
  rescue Failure => e
    { error: e.message }
  rescue EmailCampaigns::Import::ImageCompressor::Unfit
    { error: 'unfit' }
  end

  def read(src)
    return decode(src) if src.start_with?(DATA_PREFIX)

    archived = EmailCampaigns::Import::ZipReader.file_for(@files, src)
    return archived if archived
    raise Failure, 'not_in_archive' if src.start_with?(EmailCampaigns::Import::ZipReader::BASE_URL)

    download(src)
  end

  def decode(src)
    comma = src.index(',')
    raise Failure, 'unreadable' if comma.nil?

    payload = src[(comma + 1)..]
    base64 = src[0...comma].downcase.include?(BASE64_MARK)
    raise Failure, 'too_large' if (base64 ? payload.length * 3 / 4 : payload.length) > MAX_SOURCE_BYTES

    base64 ? Base64.decode64(payload) : URI.decode_uri_component(payload).b
  rescue ArgumentError
    raise Failure, 'unreadable'
  end

  def download(src)
    seconds = [FETCH_SECONDS, @deadline.remaining].min
    raise Failure, 'out_of_time' unless seconds.positive?

    SafeFetch.fetch(https(src), max_bytes: MAX_SOURCE_BYTES, total_timeout: seconds, schemes: SCHEMES,
                                allowed_content_type_prefixes: ['image/']) do |result|
      result.tempfile.read
    end
  rescue SafeFetch::FileTooLargeError
    raise Failure, 'too_large'
  rescue SafeFetch::Error
    raise Failure, 'unreachable'
  end

  # An http address is asked over https; there is no second try over http.
  def https(src)
    uri = URI.parse(src)
    raise Failure, 'unreachable' unless %w[http https].include?(uri.scheme) && uri.host.present?
    return src if uri.scheme == 'https'

    port = uri.port == uri.default_port ? nil : uri.port
    URI::HTTPS.build(host: uri.host, port: port, path: uri.path, query: uri.query).to_s
  rescue URI::InvalidURIError, URI::InvalidComponentError
    raise Failure, 'unreachable'
  end

  def upload(output, index)
    EmailCampaigns::Import::ImageUpload.call(@import, output, "imagem-#{index + 1}")
  end

  def describe(entry, copy)
    shown = { src: shown_src(entry[:src]), kind: entry[:kind], status: copy[:url] ? 'copied' : 'failed' }.compact
    shown.merge(url: copy[:url], reason: copy[:error]).compact
  end

  def shown_src(src)
    archive = EmailCampaigns::Import::ZipReader::BASE_URL
    return src.byteslice(0, REPORT_SRC_LIMIT).scrub('') if src.start_with?(DATA_PREFIX)
    return URI.decode_uri_component(src.delete_prefix(archive)) if src.start_with?(archive)

    src
  rescue ArgumentError
    src
  end

  def settle_report(copies)
    @report.remove(:images_to_copy)
    copied = copies.count { |copy| copy[:url] }
    @report.add(:images_copied, count: copied) if copied.positive?
    compressed = copies.count { |copy| copy[:compressed] }
    @report.add(:image_compressed, count: compressed) if compressed.positive?
    stilled = copies.count { |copy| copy[:animation_lost] }
    @report.add(:animation_lost, count: stilled) if stilled.positive?
  end

  def point(mjml, copies)
    EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      self.class.image_nodes(root).each { |node| point_image(node, copies[node['src']]) }
      self.class.background_nodes(root).each { |node| point_background(node, copies[node['background-url']]) }
      {}
    end
  end

  def point_image(node, copy)
    return if copy.nil?
    return node['src'] = copy[:url] if copy[:url]
    return drop_icon(node) unless node.name == 'mj-image'

    node['src'] = EmailCampaigns::Import::Placeholders::MISSING_SRC
    add_class(node, EmailCampaigns::Import::Placeholders::MISSING_CLASS)
    @report.add(:image_missing, item: node['alt'].presence)
  end

  # A social link keeps working with its network's default icon.
  def drop_icon(node)
    node.remove_attribute('src')
    @report.add(:social_icon_default)
  end

  def point_background(node, copy)
    return if copy.nil?
    return node['background-url'] = copy[:url] if copy[:url]

    BACKGROUND_ATTRIBUTES.each { |name| node.remove_attribute(name) }
    add_class(node, EmailCampaigns::Import::Placeholders::MISSING_BACKGROUND_CLASS)
    @report.add(:image_missing)
  end

  def add_class(node, name)
    node['css-class'] = (node['css-class'].to_s.split | [name]).join(' ')
  end
end
