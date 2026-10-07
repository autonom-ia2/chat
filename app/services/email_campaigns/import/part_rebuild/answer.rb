# What the AI answered for one part (#1099, delivery D), read and checked before it can touch the design. The MJML goes
# through the importer's own MJML path (MjmlSource: allowlisted attributes, the HTML inside text through the Cleaner,
# merge tags) and must come out as editable blocks only — text, image, button, divider, spacer — with nothing taken out
# for being unsafe, exactly the visible words of the original part (the same words the same number of times; order may
# follow the new columns), and exactly its links and its images: none new, none left out. An image description or a
# hint (alt, title) reaches the reader too — when images are blocked, on the mouse — so one the part did not have is
# taken out. Returns the importer's design (sections), or raises PartRebuild::Failure with the reason. JSON, Nokogiri
# and string methods — no regex.
class EmailCampaigns::Import::PartRebuild::Answer
  MAX_BYTES = 100 * 1024
  BLOCK_TAGS = %w[mj-text mj-image mj-button mj-divider mj-spacer].freeze
  REFUSED = %i[unresolved_parts unsafe_removed embed_removed template_code_removed hidden_text_removed].freeze
  BODY_TAGS = %w[<mjml <mj-body].freeze
  TEXT_TAGS = %w[mj-text mj-button].freeze
  LABELS = EmailCampaigns::Import::PartRebuild::Fragment::LABELS
  LABEL_SELECTOR = LABELS.map { |name| "[#{name}]" }.join(', ').freeze

  def self.call(text, fragment)
    new(text, fragment).call
  end

  def initialize(text, fragment)
    @text = text
    @fragment = fragment
    @report = EmailCampaigns::Import::Report.new(source_kind: 'paste')
  end

  def call
    document = known_labels(read(mjml))
    blocks = document.sections.flat_map(&:columns).flat_map(&:blocks)
    check_blocks(blocks)
    check_content(document, blocks)
    document
  end

  private

  def check_blocks(blocks)
    refuse(:empty) if blocks.empty?
    refuse(:not_editable) unless blocks.all? { |block| BLOCK_TAGS.include?(block.tag) && block.kind == :editable }
    refuse(:unsafe) if REFUSED.any? { |code| @report.count(code).positive? }
  end

  def check_content(document, blocks)
    refuse(:text_mismatch) unless words(blocks).tally == @fragment.words.tally
    check_same(links(blocks), @fragment.links, :link)
    check_same(images(document, blocks), @fragment.images, :image)
  end

  def check_same(found, original, kind)
    refuse(:"new_#{kind}") unless (found - original).empty?
    refuse(:"lost_#{kind}") unless (original - found).empty?
  end

  # The design without any alt or title the part did not have, on the blocks and in the HTML inside them.
  def known_labels(document)
    sections = document.sections.map do |section|
      section.with(columns: section.columns.map { |column| column.with(blocks: column.blocks.map { |block| labelled(block) }) })
    end
    document.with(sections: sections)
  end

  def labelled(block)
    attrs = block.attrs.reject { |name, value| LABELS.include?(name) && !known?(value) }
    content = TEXT_TAGS.include?(block.tag) ? labelled_markup(block.content) : block.content
    attrs == block.attrs && content == block.content ? block : block.with(attrs: attrs, content: content)
  end

  def labelled_markup(content)
    root = markup(content)
    odd = root.css(LABEL_SELECTOR).select { |node| unknown_labels(node).any? }
    return content if odd.empty?

    odd.each { |node| unknown_labels(node).each { |name| node.remove_attribute(name) } }
    root.to_html
  end

  def unknown_labels(node)
    LABELS.select { |name| node[name] && !known?(node[name]) }
  end

  def known?(value)
    label = EmailCampaigns::Import::PartRebuild::Fragment.label(value)
    label.empty? || @fragment.labels.include?(label)
  end

  def refuse(reason)
    raise EmailCampaigns::Import::PartRebuild::Failure, reason
  end

  def mjml
    parsed = JSON.parse(@text.to_s)
    value = parsed.is_a?(Hash) ? parsed['mjml'].to_s.strip : ''
    refuse(:empty) if value.empty?
    refuse(:too_large) if value.bytesize > MAX_BYTES
    value
  rescue JSON::ParserError
    refuse(:unreadable)
  end

  def read(value)
    source = BODY_TAGS.any? { |tag| value.start_with?(tag) } ? value : "<mjml><mj-body>#{value}</mj-body></mjml>"
    EmailCampaigns::Import::MjmlSource.call(source, @report)
  rescue EmailCampaigns::Import::Error
    refuse(:unreadable)
  end

  def words(blocks)
    blocks.flat_map do |block|
      next [] unless %w[mj-text mj-button].include?(block.tag)

      EmailCampaigns::Import::PartRebuild::Fragment.words(EmailCampaigns::Import::TableParts.words(markup(block.content)))
    end
  end

  def links(blocks)
    blocks.flat_map do |block|
      inside = TEXT_TAGS.include?(block.tag) ? markup(block.content).css('a[href]').map { |link| link['href'].to_s.strip } : []
      [block.attrs['href'], *inside].compact.map(&:strip)
    end.uniq
  end

  def images(document, blocks)
    inside = blocks.flat_map do |block|
      TEXT_TAGS.include?(block.tag) ? markup(block.content).css('img[src]').map { |image| image['src'].to_s.strip } : []
    end
    (blocks.filter_map { |block| block.attrs['src'] if block.tag == 'mj-image' } + inside + document.sections.filter_map(&:background_url)).uniq
  end

  def markup(content)
    EmailCampaigns::Import::Limits.fragment(content.to_s)
  end
end
