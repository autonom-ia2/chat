# The locked e-mail footer (#1081): legal line + {{ unsubscribe_url }} in an mj-section with
# css-class="footer-locked", which the editor makes non-removable.
#
# MJML comes from lockedFooter.json, the single source the editor also reads (block and starter
# e-mail). .ensure returns canonical MJML (MjmlCanonicalizer) with a locked section carrying the
# unsubscribe link, and never adds a second link: when the design already has one, the section that
# holds it is locked; only a design without any gets the shared footer appended. Unsubscribe merge
# tags of other platforms (`*|UNSUB|*`, `{{unsubscribe_link}}`...) are pointed at ours first.
# Links are read from the parsed MJML (attributes) and from the parsed HTML of ending tags — no regex.
class EmailCampaigns::LockedFooter
  SOURCE = Rails.root.join('app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/' \
                           'lockedFooter.json')
  MJML = JSON.parse(SOURCE.read).fetch('mjml').freeze
  CSS_CLASS = 'footer-locked'.freeze
  UNSUBSCRIBE_URL = '{{ unsubscribe_url }}'.freeze
  BODY_CLOSE = '</mj-body>'.freeze
  # Merge-tag wrappers used by e-mail platforms; longer openers first.
  MERGE_TAGS = [['{{', '}}'], ['*|', '|*'], ['[[', ']]'], ['<%', '%>'], ['%%', '%%'], ['[', ']'], ['%', '%']].freeze

  TEXT_START = MJML.index('>', MJML.index('<mj-text')) + 1

  # The shared footer with one more line (e.g. the brand) at the top of its text.
  def self.with_first_line(line)
    "#{MJML[0...TEXT_START]}#{line}<br/>#{MJML[TEXT_START..]}"
  end

  # True for the shared footer, with or without the line .with_first_line adds (canonical MJML of a locked section).
  # A footer the e-mail brought from elsewhere (imported template) is not ours.
  def self.ours?(section_mjml)
    section_mjml.start_with?(MJML[0...TEXT_START]) && section_mjml.end_with?(MJML[TEXT_START..])
  end

  def self.ensure(mjml)
    new(mjml).call
  end

  def initialize(mjml)
    @mjml = mjml.to_s
    @parsed = false
    @locked = false
  end

  def call
    out = EmailCampaigns::MjmlCanonicalizer.call(@mjml) { |root, cut| lock(root, cut) }
    return out if @locked
    # Malformed MJML is kept as written (MjmlCanonicalizer): trust a footer it visibly has.
    return out if !@parsed && out.include?(CSS_CLASS) && out.include?(UNSUBSCRIBE_URL)

    append(out)
  end

  private

  def append(mjml)
    close = mjml.rindex(BODY_CLOSE)
    return mjml + MJML if close.nil?

    "#{mjml[0...close]}#{MJML}#{mjml[close..]}"
  end

  # Called by MjmlCanonicalizer with the parsed skeleton; returns the rewritten ending-tag contents.
  def lock(root, cut)
    @parsed = true
    @cut = cut
    @slot_index = cut.slots.each_index.index_by { |index| cut.token(index) }
    @slot_changes = {}
    with_link = root.css('mj-body mj-section').select { |section| unsubscribe_link?(section) }
    @locked = with_link.any?
    target = with_link.find { |section| locked?(section) } || with_link.last
    target['css-class'] = [target['css-class'], CSS_CLASS].compact.join(' ') if target && !locked?(target)
    @slot_changes
  end

  def locked?(section)
    section['css-class'].to_s.split.include?(CSS_CLASS)
  end

  # Rewrites foreign unsubscribe merge tags in the section, then tells whether it links to ours.
  def unsubscribe_link?(section)
    hrefs = section.css('[href]').map { |element| attribute_href(element) } +
            section.css('*').filter_map { |element| @slot_index[element.text] if element.element_children.empty? }
                   .flat_map { |index| slot_hrefs(index) }
    hrefs.any? { |href| ours?(href) }
  end

  def attribute_href(element)
    element['href'] = UNSUBSCRIBE_URL if foreign?(element['href'])
    element['href']
  end

  def slot_hrefs(index)
    content = @slot_changes.fetch(index, @cut.slots[index].content)
    hrefs = content_hrefs(content)
    foreign = hrefs.select { |href| foreign?(href) }.uniq
    @slot_changes[index] = foreign.reduce(content) { |acc, href| acc.gsub(href, UNSUBSCRIBE_URL) } if foreign.any?
    hrefs.map { |href| foreign?(href) ? UNSUBSCRIBE_URL : href }
  end

  # Content nested deeper than the parser reads has no link it can vouch for (the markup cleaning drops it, #1104).
  def content_hrefs(content)
    Nokogiri::HTML5.fragment(content).css('a[href]').pluck('href')
  rescue ArgumentError
    []
  end

  def ours?(href)
    compact(href) == compact(UNSUBSCRIBE_URL)
  end

  # Another platform's unsubscribe merge tag, e.g. *|UNSUB|* or {{unsubscribe_link}}.
  def foreign?(href)
    tag = compact(href).downcase
    return false if ours?(tag)

    MERGE_TAGS.any? do |open, close|
      tag.length > open.length + close.length && tag.start_with?(open) && tag.end_with?(close) &&
        tag[open.length...-close.length].include?('unsub')
    end
  end

  def compact(value)
    value.to_s.split.join
  end
end
