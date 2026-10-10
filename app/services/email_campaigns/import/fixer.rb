# The way out of each warning that stops an import from being saved (#1099, delivery C), done on the copy the server
# keeps — the browser only says which fix it wants:
#   - kind image (an image block that is the "image to swap" placeholder, or a section whose background did not come),
#     by its position among them, found before anything is kept: `upload` a new image (checked by its bytes,
#     compressed and kept like the copied ones) or `remove` it (the block leaves; the section keeps its color);
#   - kind field (a field our campaigns cannot fill), by its key: `field` puts one of ours in its place, `text` a text
#     that is the same for everyone (written as text, never as a new field), `remove` erases it;
#   - kind part (a part the converter did not understand), by its id: `text` keeps only its text, one text block per
#     paragraph as the original showed it (PartParagraphs), `remove` takes it out. Rebuilding it with the AI is
#     delivery D.
# What blocks the saving is computed again (SaveCheck) and the fix is recorded, so the screen shows the warning solved.
# Raises EmailCampaigns::Import::Error with a code the screen explains. String methods and Nokogiri — no regex.
class EmailCampaigns::Import::Fixer
  CHOICES = { 'image' => %w[upload remove], 'field' => %w[field text remove], 'part' => %w[text remove] }.freeze
  CODES = { 'image' => 'image_missing', 'field' => 'unknown_fields', 'part' => 'unresolved_parts' }.freeze
  FIELDS = (EmailCampaigns::Import::Engine::PLACEHOLDERS - ['unsubscribe_url']).freeze
  MAX_TEXT = 200
  MAX_IMAGE_BYTES = EmailCampaigns::Import::ImageRehoster::MAX_SOURCE_BYTES
  TAG_MARKS = ['{{', '}}', '{%', '%}'].freeze

  def self.call(import, params)
    new(import, params).call
  end

  # What the screen can fix in a finished import, in the order it appears: { images:, parts:, fields: }.
  def self.targets(import)
    mjml = import.result_mjml.to_s
    images = []
    EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      images = missing(root).each_with_index.map { |node, index| image_target(node, index) }
      {}
    end
    { images: images, parts: parts(import, mjml), fields: fields(mjml) }
  end

  def self.missing(root)
    root.xpath('.//*').select do |node|
      (node.name == 'mj-image' && node['src'] == EmailCampaigns::Import::Placeholders::MISSING_SRC) ||
        node['css-class'].to_s.split.include?(EmailCampaigns::Import::Placeholders::MISSING_BACKGROUND_CLASS)
    end
  end

  def self.image_target(node, index)
    image = node.name == 'mj-image'
    { index: index, kind: image ? 'image' : 'background', alt: (node['alt'].presence if image) }
  end

  def self.parts(import, mjml)
    shown = Array(import.report['unresolved']).to_h { |part| [part['id'], part['text'].to_s] }
    ids = []
    EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      ids = root.css('mj-image').select { |node| node['src'] == EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC }.pluck('title')
      {}
    end
    ids.compact.uniq.map { |id| { id: id, text: shown.fetch(id, '') } }
  end

  def self.fields(mjml)
    EmailCampaigns::Import::TagText.keys(mjml).uniq - EmailCampaigns::Import::Engine::PLACEHOLDERS
  end

  def initialize(import, params)
    @import = import
    @kind = params[:kind].to_s
    @choice = params[:choice].to_s
    @target = params[:target].to_s
    @value = params[:value]
    @file = params[:file]
  end

  def call
    refuse(:fix_invalid) unless CHOICES.fetch(@kind, []).include?(@choice)

    @import.with_lock do
      refuse(:not_ready) unless @import.status == 'ready'

      @label = @target
      mjml = apply(@import.result_mjml.to_s)
      @import.update!(result_mjml: mjml, blocking: EmailCampaigns::Import::SaveCheck.call(mjml, @import), fixes: @import.fixes + [record])
    end
    @import
  end

  private

  def refuse(code)
    raise EmailCampaigns::Import::Error, code
  end

  def record
    { code: CODES.fetch(@kind), choice: @choice, target: @label, kind: @image_kind, value: (@kept_value if %w[field text].include?(@choice)),
      at: Time.current.iso8601 }.compact.stringify_keys
  end

  def apply(mjml)
    case @kind
    when 'image' then fix_image(mjml)
    when 'field' then fix_field(mjml)
    else fix_part(mjml)
    end
  end

  # The target is found before anything is kept: an upload for an image already solved (or one that never existed)
  # never becomes a blob of the import.
  def fix_image(mjml)
    refuse(:fix_gone) unless image_target?(mjml)

    url = upload if @choice == 'upload'
    EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      node = image_at(root)
      @image_kind = node.name == 'mj-image' ? 'image' : 'background'
      @label = node['alt'].presence
      url ? swap_image(node, url) : drop_image(node)
      {}
    end
  end

  def image_target?(mjml)
    found = false
    EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      found = image_at(root).present?
      {}
    end
    found
  end

  def image_at(root)
    index = Integer(@target, exception: false)
    self.class.missing(root)[index] if index && index >= 0
  end

  def swap_image(node, url)
    if node.name == 'mj-image'
      node['src'] = url
      remove_class(node, EmailCampaigns::Import::Placeholders::MISSING_CLASS)
    else
      node['background-url'] = url
      node['background-size'] = 'cover'
      remove_class(node, EmailCampaigns::Import::Placeholders::MISSING_BACKGROUND_CLASS)
    end
  end

  def drop_image(node)
    return node.remove if node.name == 'mj-image'

    remove_class(node, EmailCampaigns::Import::Placeholders::MISSING_BACKGROUND_CLASS)
  end

  def remove_class(node, name)
    rest = node['css-class'].to_s.split - [name]
    rest.empty? ? node.remove_attribute('css-class') : node['css-class'] = rest.join(' ')
  end

  def upload
    refuse(:image_unfit) unless @file.respond_to?(:tempfile) && @file.size.to_i.positive?
    refuse(:image_too_large) if @file.size > MAX_IMAGE_BYTES

    bytes = File.binread(@file.tempfile.path)
    type = Marcel::MimeType.for(StringIO.new(bytes)).to_s
    refuse(:image_unfit) unless EmailCampaigns::Import::ImageRehoster::RASTER_TYPES.include?(type)

    output = EmailCampaigns::Import::ImageCompressor.call(bytes, type)
    EmailCampaigns::Import::ImageUpload.call(@import, output, "troca-#{@import.images.count + 1}")
  rescue EmailCampaigns::Import::ImageCompressor::Unfit
    refuse(:image_unfit)
  end

  def fix_field(mjml)
    refuse(:fix_gone) unless self.class.fields(mjml).include?(@target)

    tag = field_replacement
    EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, cut|
      root.xpath('.//@*').each { |attribute| attribute.value = EmailCampaigns::Import::TagText.replace(attribute.value, @target, tag[:plain]) }
      cut.slots.each_with_index.to_h { |slot, index| [index, EmailCampaigns::Import::TagText.replace(slot.content, @target, tag[:html])] }
    end
  end

  def field_replacement
    case @choice
    when 'field'
      refuse(:fix_invalid) unless FIELDS.include?(@value.to_s)
      @kept_value = @value.to_s
      { plain: "{{ #{@kept_value} }}", html: "{{ #{@kept_value} }}" }
    when 'text'
      @kept_value = checked_text
      { plain: @kept_value, html: CGI.escapeHTML(@kept_value) }
    else
      { plain: '', html: '' }
    end
  end

  def checked_text
    text = @value.to_s.split.join(' ')
    refuse(:text_invalid) if text.empty? || text.length > MAX_TEXT || TAG_MARKS.any? { |mark| text.include?(mark) }
    text
  end

  def fix_part(mjml)
    refuse(:fix_gone) unless self.class.parts(@import, mjml).any? { |part| part[:id] == @target }

    paragraphs = @choice == 'text' ? part_paragraphs : []
    out = EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      node = unresolved_node(root)
      paragraphs.each { |paragraph| node.add_previous_sibling(EmailCampaigns::Import::PartParagraphs.block(node.document, paragraph)) }
      node.remove
      {}
    end
    readable(out)
  end

  # Each paragraph of the part in its own text block, as the original showed it (a title stays a title).
  def part_paragraphs
    entry = Array(@import.report['unresolved']).find { |part| part['id'] == @target } || {}
    EmailCampaigns::Import::PartParagraphs.call(entry['html'], entry['text'])
  end

  def unresolved_node(root)
    root.css('mj-image').find { |image| image['title'] == @target && image['src'] == EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC }
  end

  # The new text keeps the color it had, then goes through the same deterministic correction the import ran (contrast,
  # size) against where it lands, so text left on a dark banner (or a white title left on white) stays readable.
  def readable(mjml)
    scratch = EmailCampaigns::Import::Report.new(source_kind: 'paste')
    EmailCampaigns::Import::QualityFix.call(mjml, scratch, placeholders: EmailCampaigns::Import::Engine::PLACEHOLDERS)
  end
end
