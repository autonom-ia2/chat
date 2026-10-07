# The "how it was" side of the import screen (#1099, delivery C): the original page after the same cleaning the engine
# does (stylesheet into the tags, allowlist, hidden text and pixels out) — but with its fields as they were written
# ({{lead.nome}}, not our {{ nome }}), so it shows what the person knows, with every image pointing at the copy the
# import made of it — or a grey box of the same size when it did not come — and no link leading anywhere. The screen
# shows it in an iframe with sandbox="", so nothing of the original page runs or reports who opens the preview.
# A model that was already MJML has no separate original to show (nil), and neither has one the cleaning cannot read
# within the import's limits: the screen then shows only the result. Nokogiri and string methods — no regex.
class EmailCampaigns::Import::OriginalPreview
  MAX_BYTES = 600 * 1024
  SECONDS = 5.0
  GRAY = '#E5E7EB'.freeze
  DEFAULT_WIDTH = '100%'.freeze
  DEFAULT_HEIGHT = 120
  INTERNAL = %w[data-import-bg data-import-missing].freeze
  HEAD = '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' \
         '<style>body{margin:0}img{max-width:100%;height:auto}a{pointer-events:none}</style></head>'.freeze

  def self.call(markup, copies:, base_url: nil, charset: nil, seconds: SECONDS)
    new(markup, copies, base_url, charset, seconds).call
  end

  def initialize(markup, copies, base_url, charset, seconds)
    @markup = markup
    @copies = copies || {}
    @base_url = base_url
    @charset = charset
    @seconds = seconds
  end

  def call
    return unless @seconds.positive?

    body = cleaned_body
    return if body.nil?

    images(body)
    backgrounds(body)
    body.css('[href]').each { |node| node.remove_attribute('href') }
    html = "#{HEAD}#{body.name == 'body' ? body.to_html : "<body>#{body.inner_html}</body>"}</html>"
    html if html.bytesize <= MAX_BYTES
  rescue EmailCampaigns::Import::Error
    nil
  end

  private

  def cleaned_body
    source = EmailCampaigns::Import::Limits.source!(@markup, charset: @charset).text
    return if EmailCampaigns::Import::Limits.fragment(source).element_children.first&.name == 'mjml'

    budget = EmailCampaigns::Import::Budget.new(seconds: @seconds)
    doc = EmailCampaigns::Import::Limits.html!(source, budget)
    scratch = EmailCampaigns::Import::Report.new(source_kind: 'paste')
    EmailCampaigns::Import::StyleInliner.call(doc, scratch)
    EmailCampaigns::Import::Cleaner.call(doc.root, scratch, base_url: @base_url, tags: false)
    budget.time!
    doc.at_css('body') || doc.root
  end

  def images(body)
    body.css('img').each do |image|
      url = @copies[image['src'].to_s]
      next image['src'] = url if url

      image.replace(gray_box(image))
    end
  end

  def gray_box(image)
    box = image.document.create_element('div', 'data-import-gray' => '', 'role' => 'img', 'aria-label' => image['alt'].to_s)
    box['style'] = "display:inline-block;max-width:100%;width:#{size(image['width'], DEFAULT_WIDTH)};" \
                   "height:#{size(image['height'], "#{DEFAULT_HEIGHT}px")};background:#{GRAY}"
    box
  end

  def size(value, fallback)
    number = value.to_s.strip
    return fallback if number.empty?

    number.end_with?('%') ? number : "#{number.to_i}px"
  end

  def backgrounds(body)
    body.css('[data-import-bg]').each do |node|
      url = @copies[node['data-import-bg'].to_s]
      node['style'] = [node['style'], "background-image:url(#{url});background-size:cover"].compact.join(';') if url
    end
    INTERNAL.each { |name| body.css("[#{name}]").each { |node| node.remove_attribute(name) } }
  end
end
