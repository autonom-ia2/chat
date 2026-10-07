# What still stops an imported design from going to "Meus modelos" (#1099, delivery B), computed on the server from the
# MJML itself — never taken from the browser. The import job stores it when it finishes (for the screen to follow) and
# the saving computes it again:
#   - image_missing: an image block that is the "image to swap" placeholder, a section whose background did not come,
#     or any address of an image (`src` on any element — image blocks, social icons, defaults in mj-attributes — or a
#     section background) that is not one of this import's copies (the internet, another import, another account);
#   - unresolved_parts: a part the converter did not understand, still the placeholder image (until delivery D
#     rebuilds it, saving it would send a generic picture instead of the part);
#   - unknown_fields: a field our campaigns cannot fill (QualityGate's placeholder rule);
#   - invalid: a design that broke the rules the importer guarantees (only editable blocks, explicit close tags, one
#     locked footer with the only unsubscribe link).
# The other quality checks (contrast, sizes...) were corrected when possible during the import and only inform.
class EmailCampaigns::Import::SaveCheck
  BLOCKING_GATE_CHECKS = { placeholders: :unknown_fields, unsubscribe: :invalid, editable_tags: :invalid,
                           explicit_close_tags: :invalid, mjml_strict: :invalid }.freeze
  MAX_ITEMS = 20

  def self.call(mjml, import)
    new(mjml, import).call
  end

  def initialize(mjml, import)
    @mjml = mjml.to_s
    @import = import
    @problems = Hash.new { |hash, code| hash[code] = [] }
  end

  # [{ code:, key:, count:, items: }] — empty when the design can be saved.
  def call
    return [entry(:invalid, ['empty'])] if @mjml.strip.empty?

    check_images
    check_gate
    @problems.map { |code, items| entry(code, items) }
  end

  private

  def entry(code, items)
    { code: code, key: "#{EmailCampaigns::Import::Report::I18N_PREFIX}#{code.to_s.upcase}", count: items.size,
      items: items.compact.uniq.first(MAX_ITEMS) }
  end

  def check_images
    doc = EmailCampaigns::Import::Limits.fragment(@mjml)
    doc.css('[src]').each { |node| check_source(node) }
    doc.css('[background-url]').each { |node| check_owned(node['background-url'].to_s.strip, nil) }
    doc.css('[css-class]').each do |node|
      @problems[:image_missing] << nil if node['css-class'].split.include?(EmailCampaigns::Import::Placeholders::MISSING_BACKGROUND_CLASS)
    end
  end

  def check_source(node)
    src = node['src'].to_s.strip
    return check_owned(src, node['alt']) unless node.name == 'mj-image'
    return @problems[:unresolved_parts] << node['title'].presence if src == EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC
    return @problems[:image_missing] << node['alt'].presence if src == EmailCampaigns::Import::Placeholders::MISSING_SRC

    check_owned(src, node['alt'])
  end

  def check_owned(src, alt)
    @problems[:image_missing] << alt.presence unless EmailCampaigns::Import::PublicUrl.owned_blob(src, @import)
  end

  def check_gate
    gate = EmailCampaigns::QualityGate.new(mjml: @mjml, remote_images: true, placeholders: EmailCampaigns::Import::Engine::PLACEHOLDERS)
    gate.violations.each do |violation|
      code = BLOCKING_GATE_CHECKS[violation.check]
      @problems[code] << violation.detail.to_s if code
    end
  end
end
