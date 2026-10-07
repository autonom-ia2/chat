# What still stops an imported design from going to "Meus modelos" (#1099, delivery B), recomputed on the server from
# the MJML itself every time — never taken from the stored report nor from the browser:
#   - image_missing: an image block that is the "image to swap" placeholder, or any image or section background that is
#     not one of this import's copies (an address of the internet, of another import, of another account);
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
    doc.css('mj-image').each { |node| check_image(node['src'].to_s.strip, node['alt']) }
    doc.css('[background-url]').each { |node| check_image(node['background-url'].to_s.strip, nil, background: true) }
  end

  def check_image(src, alt, background: false)
    return if !background && src == EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC
    return @problems[:image_missing] << alt.presence if src == EmailCampaigns::Import::Placeholders::MISSING_SRC

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
