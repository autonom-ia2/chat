# Cuts the footer out of the HTML of one text block (#1099), for FooterCleaner: the line holding the unsubscribe link
# and every line after it, when together they are short enough to be a footer (TAIL_MAX_CHARS); otherwise only the
# link. Lines are the runs between line breaks, read over the text and <br> leaves in document order, so a footer
# inside inline formatting (a span around several lines) is cut just as well. Changes the fragment in place, records
# what left and returns whether the cut reached the end of the block.
class EmailCampaigns::Import::FooterCleaner::Lines
  def initialize(root, link, report)
    @root = root
    @link = link
    @report = report
    @leaves = []
    root.traverse { |node| @leaves << node if node.text? || node.name == 'br' }
  end

  def cut
    first = @leaves.index { |leaf| leaf.ancestors.include?(@link) }
    return link_only if first.nil?

    start = line_start(first)
    tail = @leaves[start..]
    return link_only if text(tail).length > EmailCampaigns::Import::FooterCleaner::TAIL_MAX_CHARS

    remove(tail + separators(start), text(tail))
    true
  end

  private

  def line_start(index)
    breaks = @leaves[0...index].each_index.select { |position| br?(@leaves[position]) }
    breaks.empty? ? 0 : breaks.last + 1
  end

  # The line breaks (and blank text) right before the footer, which would otherwise leave an empty line at the end.
  def separators(start)
    @leaves[0...start].reverse.take_while { |leaf| br?(leaf) || blank?(leaf) }
  end

  def link_only
    @report.drop_text(@link.text, :footer)
    @report.drop_link(@link['href'], :footer)
    @report.add(:unsubscribe_link_removed)
    @link.remove
    false
  end

  def remove(leaves, removed_text)
    links = @root.css('a[href]').to_a
    leaves.each(&:remove)
    prune
    gone = links.reject { |link| link.ancestors.include?(@root) }
    gone.each { |link| @report.drop_link(link['href'], :footer) }
    @report.drop_text(removed_text, :footer)
  end

  # Inline elements left without text, line break or image.
  def prune
    @root.css('*').reverse_each do |node|
      next if node.name == 'br' || node.name == 'img'

      node.remove if EmailCampaigns::Import::Visibility.visible_text(node.text).empty? && node.css('br, img').empty?
    end
  end

  def text(leaves)
    EmailCampaigns::Import::Visibility.visible_text(leaves.map { |leaf| br?(leaf) ? ' ' : leaf.content }.join)
  end

  def br?(leaf)
    leaf.element? && leaf.name == 'br'
  end

  def blank?(leaf)
    leaf.text? && EmailCampaigns::Import::Visibility.visible_text(leaf.content).empty?
  end
end
