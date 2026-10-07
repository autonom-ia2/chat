# Imports an e-mail model from another platform into editable MJML (#1099, delivery A: the pure engine). Takes pasted
# markup, an uploaded .html or the page of an address — HTML or MJML — and returns MJML made only of blocks the editor
# edits, with our locked footer, corrected for quality, plus a Report the screen turns into short sentences. It never
# touches the network: images stay at their address, listed in the report for the import job to copy (delivery B); parts
# it does not understand become marked placeholders for the AI to rebuild on request (delivery D).
#
#   result = EmailCampaigns::Import::Engine.call(html, source_kind: 'paste')
#   result.mjml   # => "<mjml>…</mjml>"
#   result.report # => EmailCampaigns::Import::Report
#
# Raises EmailCampaigns::Import::Error (with a code) when the input cannot be imported at all.
class EmailCampaigns::Import::Engine
  Result = Data.define(:mjml, :report)
  TALLIES = { texts: 'mj-text', images: 'mj-image', buttons: 'mj-button', dividers: 'mj-divider', spacers: 'mj-spacer' }.freeze
  SOURCE_KINDS = %w[paste file url].freeze
  PLACEHOLDERS = (EmailCampaigns::TemplateValidator::DEFAULT_KEYS + EmailCampaigns::Import::MergeTags::Catalog::LIST_FIELDS).freeze

  def self.call(input, source_kind:, base_url: nil)
    new(input, source_kind, base_url).call
  end

  def initialize(input, source_kind, base_url)
    @input = input
    @source_kind = source_kind.to_s
    @base_url = base_url
    @report = EmailCampaigns::Import::Report.new(source_kind: @source_kind)
  end

  def call
    raise EmailCampaigns::Import::Error, :invalid_source_kind unless SOURCE_KINDS.include?(@source_kind)

    source = EmailCampaigns::Import::Limits.source!(@input)
    reader = mjml?(source) ? EmailCampaigns::Import::MjmlSource : EmailCampaigns::Import::HtmlSource
    document = EmailCampaigns::Import::FooterCleaner.call(reader.call(source, @report, base_url: @base_url), @report)
    raise EmailCampaigns::Import::Error, :empty if document.sections.empty?

    Result.new(mjml: finish(document), report: @report)
  end

  private

  def mjml?(source)
    Nokogiri::HTML5.fragment(source).element_children.first&.name == 'mjml'
  end

  def finish(document)
    @report.title = document.title
    @report.preheader ||= document.preview
    @report.editable_area_ratio = EmailCampaigns::Import::EditableArea.ratio(document)
    tally(document)
    @report.images = EmailCampaigns::Import::ImageList.from(document)
    @report.add(:images_to_copy, count: @report.images.size) if @report.images.any?
    mjml = EmailCampaigns::LockedFooter.ensure(EmailCampaigns::Import::Emitter.call(document))
    EmailCampaigns::Import::QualityFix.call(mjml, @report, placeholders: PLACEHOLDERS)
  end

  def tally(document)
    columns = document.sections.flat_map(&:columns)
    blocks = columns.flat_map(&:blocks)
    @report.tally(:sections, document.sections.size)
    @report.tally(:columns, columns.size)
    TALLIES.each { |kind, tag| @report.tally(kind, blocks.count { |block| block.tag == tag && block.kind != :unresolved }) }
    @report.tally(:unresolved, blocks.count { |block| block.kind == :unresolved })
  end
end
