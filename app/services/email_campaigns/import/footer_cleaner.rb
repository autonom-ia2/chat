# Takes the footer of the platform a model came from out of the importer's design (#1099) — and only the footer. A link
# to unsubscribe (our {{ unsubscribe_url }} after the merge tags, or an address whose path reads as unsubscribe) marks
# where it starts: in a text block, the line holding the link and the lines after it leave, while the text before it
# stays — body copy often shares the block with the footer. When what follows the link is too long to be a footer, only
# the link leaves, with a warning. A button, image or social icon pointing at it leaves on its own, together with the
# small badges right after the footer. The locked footer (LockedFooter.ensure) then brings the only link and the legal
# line. Everything taken out is recorded.
class EmailCampaigns::Import::FooterCleaner
  UNSUBSCRIBE_PATHS = %w[unsubscribe unsub descadastr cancelar-inscricao cancelar_inscricao optout opt-out opt_out].freeze
  UNSUBSCRIBE = '{{ unsubscribe_url }}'.freeze
  BADGE_MAX_WIDTH = 150
  # The most text a footer (from the unsubscribe line to the end of its block) can hold.
  TAIL_MAX_CHARS = 300

  def self.call(document, report)
    new(report).call(document)
  end

  def initialize(report)
    @report = report
    @removed = false
  end

  def call(document)
    sections = document.sections.filter_map do |section|
      columns = section.columns.filter_map do |column|
        blocks = clean(column.blocks)
        column.with(blocks: blocks) if blocks.any?
      end
      section.with(columns: columns) if columns.any?
    end
    @report.add(:footer_replaced) if @removed
    document.with(sections: sections)
  end

  private

  def clean(blocks)
    dropping = false
    blocks.filter_map do |block|
      kept, footer_end = cut(block, dropping)
      dropping = footer_end
      kept
    end
  end

  # [the block as it stays (nil when it leaves), whether a footer reached its end].
  def cut(block, dropping)
    return drop(block) if dropping && badge?(block)
    return [block, false] unless unsubscribe?(block)

    case block.tag
    when 'mj-text' then text_cut(block)
    when 'mj-social' then social_cut(block)
    else drop(block)
    end
  end

  def unsubscribe?(block)
    hrefs(block).any? { |href| unsubscribe_href?(href) }
  end

  def unsubscribe_href?(href)
    href.split.join == UNSUBSCRIBE.split.join || unsubscribe_path?(href)
  end

  def unsubscribe_path?(href)
    return false unless EmailCampaigns::Import::Url.http?(href)

    path = EmailCampaigns::Import::Url.path(href).downcase
    UNSUBSCRIBE_PATHS.any? { |marker| path.include?(marker) }
  end

  def badge?(block)
    return false unless block.tag == 'mj-image'

    width = EmailCampaigns::Import::StyleMap.px(block.attrs['width'].to_s)
    width.present? && width <= BADGE_MAX_WIDTH
  end

  # Links of a block: its own href, and those of the links and social icons inside it.
  def hrefs(block)
    [block.attrs['href'], *Nokogiri::HTML5.fragment(block.content.to_s).css('[href]').pluck('href')].compact
  end

  def drop(block)
    @report.drop_text(EmailCampaigns::Import::TableParts.words(Nokogiri::HTML5.fragment(block.content.to_s)), :footer)
    hrefs(block).each { |href| @report.drop_link(href, :footer) }
    @report.drop_image(block.attrs['src'], :footer) if block.tag == 'mj-image'
    @report.tally(:footer_blocks_removed)
    @removed = true
    [nil, true]
  end

  def text_cut(block)
    root = Nokogiri::HTML5.fragment(block.content.to_s)
    footer_end = false
    while (link = root.css('a[href]').find { |node| unsubscribe_href?(node['href']) })
      footer_end = EmailCampaigns::Import::FooterCleaner::Lines.new(root, link, @report).cut || footer_end
    end
    @removed = true
    return [nil, footer_end] if EmailCampaigns::Import::TableParts.visible(root).empty? && root.css('img').empty?

    [block.with(content: root.to_html.strip), footer_end]
  end

  def social_cut(block)
    root = Nokogiri::HTML5.fragment(block.content.to_s)
    root.css('[href]').select { |node| unsubscribe_href?(node['href']) }.each do |element|
      @report.drop_text(element.text, :footer)
      @report.drop_link(element['href'], :footer)
      element.remove
    end
    @removed = true
    return [nil, true] if root.element_children.empty?

    [block.with(content: root.to_html.strip), true]
  end
end
