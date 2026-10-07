# The blocks of an e-mail, for "Ajustar com IA" (#1095): the top-level children of <mj-body> of the
# canonical MJML, each with the exact source it has there. The model answers with the list of blocks
# of the adjusted e-mail — the id of a block it keeps, or the MJML of a block it rewrote or added — and
# #assemble rebuilds the e-mail from it. Kept blocks come back byte for byte; the head and the locked
# footer are never handed to the model and always come back as they were. Plain string scanning on the
# skeleton of MjmlEndingContent (text and comments cut out) — no regex.
class EmailCampaigns::Ai::MjmlSections
  Section = Struct.new(:id, :mjml, :locked)
  ID_PREFIX = 'b'.freeze

  attr_reader :unknown_ids

  # nil when the MJML has no <mj-body> or its tags do not balance (it cannot be split safely).
  def self.parse(mjml)
    canonical = EmailCampaigns::LockedFooter.ensure(mjml)
    cut = EmailCampaigns::MjmlEndingContent.new(canonical)
    ranges = Scanner.new(cut.skeleton).call
    return nil if ranges.nil?

    prefix, blocks, suffix = ranges
    new(cut.restore(prefix), blocks.map { |block| cut.restore(block) }, cut.restore(suffix))
  end

  def initialize(prefix, blocks, suffix)
    @prefix = prefix
    @suffix = suffix
    @unknown_ids = []
    @sections = number(blocks)
  end

  def canonical
    @prefix + @sections.map(&:mjml).join + @suffix
  end

  def editable
    @sections.reject(&:locked)
  end

  # items: [{ 'keep' => id, 'mjml' => '' }, { 'keep' => '', 'mjml' => '<mj-section>...' }]. Unknown ids
  # are left out and listed in #unknown_ids. The locked footer goes back last, as it was — or, when the adjustment
  # applied another identity (#1126), as `footer` (that identity's BrandKits::FooterMjml) if it was our own footer.
  def assemble(items, footer: nil)
    by_id = editable.index_by(&:id)
    @unknown_ids = []
    body = Array(items).filter_map { |item| block_for(item.to_h, by_id) }
    @prefix + body.join + locked_footer(footer) + @suffix
  end

  private

  def locked_footer(footer)
    @sections.select(&:locked).map do |section|
      footer.present? && EmailCampaigns::LockedFooter.ours?(section.mjml) ? footer : section.mjml
    end.join
  end

  def block_for(item, by_id)
    keep = item['keep'].to_s.strip
    return item['mjml'].to_s.strip.presence if keep.empty?

    section = by_id[keep]
    @unknown_ids << keep if section.nil?
    section&.mjml
  end

  def number(blocks)
    count = 0
    blocks.map do |mjml|
      locked = locked?(mjml)
      count += 1 unless locked
      Section.new(locked ? nil : "#{ID_PREFIX}#{count}", mjml, locked)
    end
  end

  def locked?(mjml)
    EmailCampaigns::QualityGate.footer_sections(Nokogiri::HTML5.fragment(mjml)).any?
  end
end
