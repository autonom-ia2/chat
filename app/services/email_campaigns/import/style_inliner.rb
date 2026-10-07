# Writes the <style> rules of an imported model into its tags (#1099), so the colors, sizes and paddings set by class
# reach the converter, which reads inline styles only. css_parser reads the stylesheet (never following @import);
# Nokogiri matches the selectors. Only rules for every medium apply — media queries (mobile, dark mode) and pseudo
# selectors are left out. Cascade: rules by specificity and order, then inline, then !important rules over normal
# inline. Bounded by Limits::MAX_CSS_RULES and a time budget of its own; past either it stops and reports.
class EmailCampaigns::Import::StyleInliner
  Entry = Struct.new(:specificity, :order, :important, :property, :value)
  Rule = Struct.new(:selector, :declarations)

  def self.call(doc, report, deadline: EmailCampaigns::Import::Limits::CSS_SECONDS, clock: nil)
    new(doc, report, deadline: deadline, clock: clock).call
  end

  def initialize(doc, report, deadline:, clock:)
    @doc = doc
    @report = report
    @deadline = deadline
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  end

  def call
    sheets = @doc.css('style')
    css = sheets.map(&:content).join("\n")
    sheets.each(&:remove)
    flag_ignored(css)
    rules = parse(css)
    apply(collect(rules)) if rules.any?
    @doc
  end

  private

  def flag_ignored(css)
    lower = css.downcase
    @report.add(:dark_mode_ignored) if lower.include?('prefers-color-scheme') || lower.include?('data-ogsc')
    fonts = lower.include?('@font-face') || lower.include?('@import') || @doc.css('link[rel~="stylesheet"]').any?
    @report.add(:web_font_ignored) if fonts
  end

  def parse(css)
    return [] if css.strip.empty?

    parser = CssParser::Parser.new(import: false, absolute_paths: false)
    parser.add_block!(css)
    rules = []
    parser.each_rule_set(:all) do |rule_set, media_types|
      next unless media_types == [:all]

      declarations = []
      rule_set.each_declaration { |property, value, important| declarations << [property.downcase, value, important] }
      rule_set.selectors.each { |selector| rules << Rule.new(selector.strip, declarations) }
    end
    rules
  rescue StandardError
    @report.add(:styles_dropped)
    []
  end

  def collect(rules)
    started = @clock.call
    entries = Hash.new { |hash, node| hash[node] = [] }
    rules.each_with_index do |rule, order|
      break @report.add(:css_limit) if order >= EmailCampaigns::Import::Limits::MAX_CSS_RULES || @clock.call - started > @deadline
      next unless usable?(rule.selector)

      specificity = CssParser.calculate_specificity(rule.selector)
      matches(rule.selector).each do |node|
        rule.declarations.each { |property, value, important| entries[node] << Entry.new(specificity, order, important, property, value) }
      end
    end
    entries
  end

  def usable?(selector)
    !selector.empty? && selector.exclude?(':') && !selector.start_with?('@') && selector.exclude?('%')
  end

  def matches(selector)
    @doc.css(selector)
  rescue Nokogiri::CSS::SyntaxError, Nokogiri::XML::XPath::SyntaxError
    []
  end

  def apply(entries)
    entries.each do |node, list|
      final = cascade(list, EmailCampaigns::Import::StyleMap.parse(node['style']))
      node['style'] = EmailCampaigns::Import::StyleMap.dump(final.transform_values { |value| EmailCampaigns::Import::StyleMap.plain(value) })
    end
  end

  # Normal rules by specificity and order, then the inline style, then !important rules over normal inline values.
  def cascade(list, inline)
    important, normal = list.sort_by { |entry| [entry.specificity, entry.order] }.partition(&:important)
    final = normal.to_h { |entry| [entry.property, entry.value] }.merge(inline)
    important.each do |entry|
      final[entry.property] = entry.value unless EmailCampaigns::Import::StyleMap.important?(inline[entry.property])
    end
    final
  end
end
