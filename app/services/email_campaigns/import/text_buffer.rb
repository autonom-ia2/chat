# Collects the running text of one column of an imported model (#1099) as paragraphs with their style, keeping inline
# formatting (strong, em, links, colored spans) balanced across paragraph breaks. Adjacent paragraphs with the same
# style become one mj-text — a blank line between paragraphs, a line break between list items and table lines.
class EmailCampaigns::Import::TextBuffer
  Paragraph = Struct.new(:style, :kind, :html, :filled)
  LINE_KINDS = %i[item line].freeze
  SPACE_CHARS = [' ', "\t", "\n", "\r", "\f"].freeze

  def initialize
    @paragraphs = []
    @current = nil
    @open = []
    @next_style = nil
    @next_kind = :para
  end

  def text(content, style)
    collapsed = collapse(content)
    return if collapsed.strip.empty? && !@current&.filled

    start(style)
    @current.html << escape(collapsed)
    @current.filled ||= !EmailCampaigns::Import::Visibility.visible_text(collapsed).empty?
  end

  def line_break
    @current.html << '<br/>' if @current&.filled
  end

  # The following text starts a new paragraph of this style and kind.
  def paragraph(style, kind = :para)
    close_paragraph
    @next_style = style
    @next_kind = kind
  end

  def open_inline(opening, closing)
    @open << [opening, closing]
    @current.html << opening if @current
  end

  def close_inline
    _opening, closing = @open.pop
    @current.html << closing if @current && closing
  end

  # The groups collected so far, as [style, html] pairs; the buffer starts over (inline tags stay open).
  def drain
    close_paragraph
    groups = group(@paragraphs)
    @paragraphs = []
    groups
  end

  private

  def start(style)
    return if @current

    @current = Paragraph.new(@next_style || style, @next_kind, +'', false)
    @open.each { |pair| @current.html << pair.first }
  end

  def close_paragraph
    return unless @current

    @open.reverse_each { |_opening, closing| @current.html << closing }
    @paragraphs << @current if @current.filled
    @current = nil
  end

  def group(paragraphs)
    paragraphs.slice_when { |first, second| first.style.key != second.style.key }.map do |run|
      html = run.each_with_index.map do |paragraph, index|
        next tidy(paragraph.html) if index.zero?

        joiner = LINE_KINDS.include?(paragraph.kind) && LINE_KINDS.include?(run[index - 1].kind) ? '<br/>' : '<br/><br/>'
        "#{joiner}#{tidy(paragraph.html)}"
      end.join
      [run.first.style, html]
    end
  end

  # Drops inline tags left empty by a paragraph break and the spaces and breaks at the edges.
  def tidy(html)
    fragment = Nokogiri::HTML5.fragment(html)
    fragment.css('a, strong, em, span').reverse_each do |node|
      node.remove if EmailCampaigns::Import::Visibility.visible_text(node.text).empty? && node.css('br').empty?
    end
    out = fragment.to_html.strip
    out = out.delete_suffix('<br>').rstrip while out.end_with?('<br>')
    out = out.delete_prefix('<br>').lstrip while out.start_with?('<br>')
    out
  end

  def collapse(content)
    out = +''
    content.each_char do |char|
      if SPACE_CHARS.include?(char)
        out << ' ' unless out.end_with?(' ')
      else
        out << char
      end
    end
    out
  end

  def escape(text)
    text.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub(EmailCampaigns::Import::Url::NBSP, '&nbsp;')
  end
end
