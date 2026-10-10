require 'open3'

# The pages of the import fidelity suite (#1099, delivery D). For each model in spec/fixtures/email_imports it writes two
# pages a browser compares (scripts/email-import-fidelity/shoot.mjs):
#   - original.html: the original after the same cleaning the import does (OriginalPreview) — or, for a model that was
#     MJML already, that MJML compiled;
#   - imported.html: what the import produced, compiled with mjml-browser (EmailCampaigns::MjmlCompiler).
# On both sides every image is the same grey box (the width the page gives it, the height the original declared, or
# DEFAULT_HEIGHT), and nothing is loaded from the network, so what differs is layout and text, not pictures. It also
# writes manifest.json with each model's editable area (EditableArea, by visible area) against the GOAL of 70%. Needs
# Node and the frontend dependencies (the MJML compiler), like the engine fidelity spec. Nokogiri only — no regex.
class EmailImportFidelity::Pages
  GOAL = 0.70
  WIDTHS = [600, 375].freeze
  GRAY = EmailCampaigns::Import::OriginalPreview::GRAY
  DEFAULT_HEIGHT = EmailCampaigns::Import::OriginalPreview::DEFAULT_HEIGHT
  FIXTURES = Rails.root.join('spec/fixtures/email_imports')
  OFFLINE = %w[link script].freeze
  SOFT_COMPILER = Rails.root.join('scripts/email-import-fidelity/mjml-soft.mjs').freeze

  def self.call(out_dir, fixtures: FIXTURES, only: nil)
    new(Pathname(out_dir), Pathname(fixtures), only).call
  end

  def initialize(out_dir, fixtures, only)
    @out_dir = out_dir
    @fixtures = fixtures
    @only = only
  end

  def call
    entries = files.map { |file| page(file) }
    manifest = { goal: GOAL, widths: WIDTHS, generated_at: Time.current.iso8601, fixtures: entries }
    FileUtils.mkdir_p(@out_dir)
    File.write(@out_dir.join('manifest.json'), JSON.pretty_generate(manifest))
    manifest
  end

  private

  def files
    all = @fixtures.glob('*.html').sort
    @only ? all.select { |file| Array(@only).include?(file.basename('.html').to_s) } : all
  end

  def page(file)
    name = file.basename('.html').to_s
    markup = file.binread
    result = EmailCampaigns::Import::Engine.call(markup, source_kind: 'file')
    compiled = EmailCampaigns::MjmlCompiler.call(result.mjml)
    heights = declared_heights(markup)
    dir = @out_dir.join(name)
    FileUtils.mkdir_p(dir)
    File.write(dir.join('original.html'), original(markup, heights))
    File.write(dir.join('imported.html'), grayed(compiled.html, heights))
    entry(name, result.report, compiled)
  rescue EmailCampaigns::Import::Error => e
    { name: name, error: e.code.to_s }
  end

  def entry(name, report, compiled)
    ratio = report.editable_area_ratio.to_f
    { name: name, editable_area_ratio: ratio, goal_met: ratio >= GOAL, unresolved_parts: report.counts[:unresolved].to_i,
      mjml_errors: compiled.errors.size, original: "#{name}/original.html", imported: "#{name}/imported.html" }
  end

  def original(markup, heights)
    cleaned = EmailCampaigns::Import::OriginalPreview.call(markup, copies: {}, seconds: 10)
    return offline(cleaned) if cleaned

    grayed(soft_compiled(markup.dup.force_encoding(Encoding::UTF_8).scrub('')), heights)
  end

  # A model that was MJML already, compiled as its author wrote it (soft validation: strict refuses what the import
  # itself takes apart, like mj-raw).
  def soft_compiled(mjml)
    output, _error, status = Open3.capture3('node', SOFT_COMPILER.to_s, stdin_data: mjml, chdir: Rails.root.to_s)
    status.success? ? output : ''
  end

  # The height each image of the original declared, by its address, so the imported side draws the same box.
  def declared_heights(markup)
    doc = Nokogiri::HTML5(markup.dup.force_encoding(Encoding::UTF_8).scrub(''))
    doc.css('img[src], mj-image[src]').each_with_object({}) do |image, out|
      height = image['height'].to_s.strip
      out[image['src'].to_s.strip] = height.to_i if height.to_i.positive? && !height.end_with?('%')
    end
  end

  def grayed(html, heights)
    doc = Nokogiri::HTML5(html.to_s)
    doc.css('img').each { |image| image.replace(box(image, heights)) }
    offline(doc.to_html)
  end

  def box(image, heights)
    width = box_width(image['width'].to_s.strip)
    height = heights[image['src'].to_s.strip] || DEFAULT_HEIGHT
    node = image.document.create_element('div', 'data-import-gray' => '')
    node['style'] = "display:inline-block;max-width:100%;width:#{width};height:#{height}px;background:#{GRAY}"
    node
  end

  def box_width(value)
    return '100%' if value.to_i <= 0

    value.end_with?('%') ? value : "#{value.to_i}px"
  end

  # Nothing of the page reaches the network: external stylesheets and their @import lines (web fonts) and scripts leave.
  def offline(html)
    doc = Nokogiri::HTML5(html.to_s)
    doc.css(OFFLINE.join(', ')).each(&:remove)
    doc.css('style').each { |style| style.content = style.content.lines.reject { |line| line.include?('@import') }.join }
    doc.to_html
  end
end
