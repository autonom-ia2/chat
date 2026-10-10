# Puts a rebuilt part (#1099, delivery D) where its placeholder image is. When the placeholder sits in a section of one
# column, the section is split around it — what came before and after stays in copies of that section — and the part's
# own sections go in between, taking the section's background color (and, when the part was the whole section and is
# one section, its background image and padding) wherever the AI set none. In a section of several columns the part's
# blocks go in the placeholder's column, one under the other (see in_column). The new markup is written by the importer's Emitter and
# placed where a marker comment was left; the MJML is canonical again afterwards (LockedFooter.ensure). Nokogiri and
# string methods — no regex.
class EmailCampaigns::Import::PartRebuild::Splice
  MARK = 'import-rebuild'.freeze

  def self.call(mjml, target, document)
    new(mjml, target, document).call
  end

  def initialize(mjml, target, document)
    @mjml = mjml
    @target = target
    @document = document
    @markup = nil
  end

  def call
    marked = EmailCampaigns::MjmlCanonicalizer.call(@mjml) do |root, _cut|
      place(placeholder(root))
      {}
    end
    fill_marker(marked)
  end

  private

  def placeholder(root)
    found = root.css('mj-image').find do |node|
      node['title'] == @target && node['src'] == EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC
    end
    found || raise(EmailCampaigns::Import::PartRebuild::Failure, :gone)
  end

  def place(node)
    column = node.parent
    section = column&.parent
    return split(section, column, node) if one_column?(section, column)

    in_column(column, node)
  end

  # In a section of several columns the part's blocks stack in the placeholder's column. A column has no background
  # image, so an answer with one is refused (it would be copied and then dropped); a background color goes to the column
  # when the part was the whole column and the column had none.
  def in_column(column, node)
    refuse(:not_placeable) if @document.sections.any? { |part| part.background_url || part.background_missing }
    paint(column)
    node.add_previous_sibling(marker(node.document))
    node.remove
    @markup = EmailCampaigns::Import::Emitter.blocks(@document.sections.flat_map(&:columns).flat_map(&:blocks))
  end

  def paint(column)
    colors = @document.sections.map(&:background).uniq
    return unless colors.one? && colors.first && whole_column?(column)

    column['background-color'] = colors.first
  end

  def whole_column?(column)
    column&.name == 'mj-column' && column.element_children.one? && column['background-color'].blank?
  end

  def refuse(reason)
    raise EmailCampaigns::Import::PartRebuild::Failure, reason
  end

  def one_column?(section, column)
    column&.name == 'mj-column' && section&.name == 'mj-section' && section.element_children.one?
  end

  def split(section, column, node)
    before = column.element_children.index(node)
    after = column.element_children.size - before - 1
    section.add_previous_sibling(part_of(section, 0...before)) if before.positive?
    section.add_previous_sibling(marker(section.document))
    section.add_previous_sibling(part_of(section, (before + 1)..)) if after.positive?
    @markup = EmailCampaigns::Import::Emitter.sections(inherit(section, alone: before.zero? && after.zero?))
    section.remove
  end

  # A copy of the section keeping only the blocks at `range` of its column.
  def part_of(section, range)
    copy = section.dup
    blocks = copy.element_children.first.element_children
    keep = blocks.to_a[range]
    blocks.each { |block| block.remove unless keep.include?(block) }
    copy
  end

  def inherit(section, alone:)
    color = EmailCampaigns::Import::StyleMap.color(section['background-color'].to_s)
    whole = alone && @document.sections.one?
    @document.sections.map { |part| with_section_look(part, section, color, whole) }
  end

  def with_section_look(part, section, color, whole)
    part = part.with(background: color) if part.background.nil? && color
    return part unless whole

    part.with(background_url: part.background_url || section['background-url'].presence, padding: part.padding || section['padding'].presence)
  end

  def marker(document)
    Nokogiri::XML::Comment.new(document, mark)
  end

  def mark
    "#{MARK} #{@target}"
  end

  def fill_marker(marked)
    comment = "<!--#{mark}-->"
    at = marked.index(comment)
    raise EmailCampaigns::Import::PartRebuild::Failure, :gone if at.nil?

    "#{marked[0...at]}#{@markup}#{marked[(at + comment.length)..]}"
  end
end
