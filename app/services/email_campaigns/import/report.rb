# What a template import did (#1099), in counts and lists the import screen turns into short sentences. Warning keys are
# i18n keys (EMAIL_IMPORT.REPORT.<CODE>) with a severity: blocking ones (an unknown field, an image that did not come)
# stop the saving until solved, the others only inform. Nothing here names the platform a model came from. Dropped
# texts, links and images keep the reason they left, so the fidelity suite (and the screen) can account for each one.
class EmailCampaigns::Import::Report
  VERSION = 1
  I18N_PREFIX = 'EMAIL_IMPORT.REPORT.'.freeze
  SEVERITIES = {
    blocking: %i[unknown_fields image_missing],
    warning: %i[unresolved_parts unsafe_removed unsafe_css_removed hidden_text_removed conditional_simplified tag_simplified
                link_removed redirect_kept embed_removed video_as_image dark_mode_ignored web_font_ignored styles_dropped
                include_ignored css_limit layout_stacked table_as_text outlook_only quality_pending gmail_clip],
    info: %i[images_to_copy tags_converted platform_tags_removed footer_replaced tracking_removed preheader_kept link_unwrapped
             vml_button_recovered hero_converted navbar_converted accordion_converted carousel_converted font_replaced quality_fixed]
  }.freeze
  SEVERITY = SEVERITIES.flat_map { |severity, codes| codes.map { |code| [code, severity] } }.to_h.freeze
  MAX_ITEMS = 50
  MAX_FRAGMENT_BYTES = 20 * 1024

  attr_reader :source_kind, :dropped_texts, :dropped_links, :dropped_images, :rewritten_links, :unresolved, :recovered_texts,
              :counts
  attr_accessor :title, :preheader, :editable_area_ratio, :images

  def initialize(source_kind:)
    @source_kind = source_kind
    @warnings = {}
    @counts = Hash.new(0)
    @dropped_texts = []
    @dropped_links = []
    @dropped_images = []
    @rewritten_links = []
    @unresolved = []
    @recovered_texts = []
    @images = []
  end

  def add(code, count: 1, item: nil)
    raise ArgumentError, "unknown import report code #{code}" unless SEVERITY.key?(code)

    entry = (@warnings[code] ||= { count: 0, items: [] })
    entry[:count] += count
    entry[:items] << item if item && entry[:items].size < MAX_ITEMS && entry[:items].exclude?(item)
  end

  def count(code)
    @warnings.dig(code, :count).to_i
  end

  def items(code)
    @warnings.dig(code, :items) || []
  end

  def tally(kind, amount = 1)
    @counts[kind] += amount
  end

  def drop_text(text, reason)
    clean = text.to_s.split.join(' ')
    @dropped_texts << { text: clean, reason: reason } unless clean.empty?
  end

  def drop_link(href, reason)
    @dropped_links << { href: href.to_s.strip, reason: reason } unless href.to_s.strip.empty?
  end

  def drop_image(src, reason)
    @dropped_images << { src: src.to_s.strip, reason: reason } unless src.to_s.strip.empty?
  end

  def rewrite_link(from, to)
    @rewritten_links << { from: from, to: to }
  end

  def recover_text(text)
    @recovered_texts << text.to_s.split.join(' ')
  end

  # Registers a part the converter left for later and returns the id its placeholder image carries.
  def add_unresolved(text:, html:)
    id = "trecho-#{@unresolved.size + 1}"
    @unresolved << { id: id, text: text.to_s.split.join(' '), html: html.to_s.byteslice(0, MAX_FRAGMENT_BYTES).scrub('') }
    add(:unresolved_parts, item: id)
    id
  end

  def to_h
    {
      version: VERSION, source_kind: source_kind, title: title, preheader: preheader, editable_area_ratio: editable_area_ratio,
      counts: counts.to_h, warnings: warnings, images: images, unresolved: unresolved,
      dropped: { texts: dropped_texts, links: dropped_links, images: dropped_images }, rewritten_links: rewritten_links
    }
  end

  private

  def warnings
    SEVERITIES.flat_map do |severity, codes|
      codes.filter_map do |code|
        entry = @warnings[code]
        next unless entry

        { key: "#{I18N_PREFIX}#{code.to_s.upcase}", code: code, severity: severity, count: entry[:count], items: entry[:items] }
      end
    end
  end
end
