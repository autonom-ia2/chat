# What the AI answered for one part (#1099, delivery D), read and checked before it can touch the design. The MJML goes
# through the importer's own MJML path (MjmlSource: allowlisted attributes, the HTML inside text through the Cleaner,
# merge tags) and must come out as editable blocks only — text, image, button, divider, spacer — with nothing taken out
# for being unsafe, exactly the visible words of the original part (the same words the same number of times; order may
# follow the new columns) and no link or image the part did not have. Returns the importer's design (sections), or
# raises PartRebuild::Failure with the reason. JSON, Nokogiri and string methods — no regex.
class EmailCampaigns::Import::PartRebuild::Answer
  MAX_BYTES = 100 * 1024
  BLOCK_TAGS = %w[mj-text mj-image mj-button mj-divider mj-spacer].freeze
  REFUSED = %i[unresolved_parts unsafe_removed embed_removed template_code_removed hidden_text_removed].freeze
  BODY_TAGS = %w[<mjml <mj-body].freeze

  def self.call(text, fragment)
    new(text, fragment).call
  end

  def initialize(text, fragment)
    @text = text
    @fragment = fragment
    @report = EmailCampaigns::Import::Report.new(source_kind: 'paste')
  end

  def call
    document = read(mjml)
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
    refuse(:new_link) unless (links(blocks) - @fragment.links).empty?
    refuse(:new_image) unless (images(document, blocks) - @fragment.images).empty?
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
      inside = block.tag == 'mj-text' ? markup(block.content).css('a[href]').map { |link| link['href'].to_s.strip } : []
      [block.attrs['href'], *inside].compact.map(&:strip)
    end.uniq
  end

  def images(document, blocks)
    (blocks.filter_map { |block| block.attrs['src'] if block.tag == 'mj-image' } + document.sections.filter_map(&:background_url)).uniq
  end

  def markup(content)
    EmailCampaigns::Import::Limits.fragment(content.to_s)
  end
end
