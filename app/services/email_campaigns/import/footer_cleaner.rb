# Takes the footer of the platform a model came from out of the importer's design (#1099): the text block holding an
# unsubscribe link — our {{ unsubscribe_url }} after the merge tags, or an address whose path reads as unsubscribe —
# together with the small badges right after it. The locked footer (LockedFooter.ensure) then brings the only link and
# the legal line. Everything taken out is recorded.
class EmailCampaigns::Import::FooterCleaner
  UNSUBSCRIBE_PATHS = %w[unsubscribe unsub descadastr cancelar-inscricao cancelar_inscricao optout opt-out opt_out].freeze
  UNSUBSCRIBE = '{{ unsubscribe_url }}'.freeze
  BADGE_MAX_WIDTH = 150

  def self.call(document, report)
    new(report).call(document)
  end

  def initialize(report)
    @report = report
  end

  def call(document)
    sections = document.sections.filter_map do |section|
      columns = section.columns.filter_map do |column|
        blocks = clean(column.blocks)
        column.with(blocks: blocks) if blocks.any?
      end
      section.with(columns: columns) if columns.any?
    end
    @report.add(:footer_replaced)
    document.with(sections: sections)
  end

  private

  def clean(blocks)
    dropping = false
    blocks.reject do |block|
      remove = unsubscribe?(block) || (dropping && badge?(block))
      dropping = remove
      drop(block) if remove
      remove
    end
  end

  def unsubscribe?(block)
    hrefs(block).any? { |href| href.split.join == UNSUBSCRIBE.split.join || unsubscribe_path?(href) }
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

  def hrefs(block)
    [block.attrs['href'], *Nokogiri::HTML5.fragment(block.content.to_s).css('a[href]').pluck('href')].compact
  end

  def drop(block)
    @report.drop_text(EmailCampaigns::Import::TableParts.words(Nokogiri::HTML5.fragment(block.content.to_s)), :footer)
    hrefs(block).each { |href| @report.drop_link(href, :footer) }
    @report.drop_image(block.attrs['src'], :footer) if block.tag == 'mj-image'
    @report.tally(:footer_blocks_removed)
  end
end
