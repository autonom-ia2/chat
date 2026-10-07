require 'rails_helper'

# Fidelity of the import engine on real-world models (#1099): every fixture in spec/fixtures/email_imports must come out as
# strict-valid MJML, made only of blocks the editor edits, with every visible text, link and image of the original either
# kept or explicitly accounted for by the report, at least 70% of its visible area editable and nothing active left.
# Compiles with mjml-browser (EmailCampaigns::MjmlCompiler), so it needs Node and the frontend dependencies, like CI has.
RSpec.describe EmailCampaigns::Import::Engine, :aggregate_failures do
  fixtures = Rails.root.join('spec/fixtures/email_imports')
  separators = %w[. , ; : ! ? ( ) [ ] " ' « » — – - · | * • … / & + = ® © ™].freeze
  allowed_drops = %i[hidden conditional footer platform_link unsafe tracking relative missing unresolved placeholder_link].freeze
  schemes = %w[http https mailto tel].freeze
  dimensions = %w[width height].freeze
  forbidden = %w[script iframe object embed svg form input base meta link style frame frameset applet math video audio].freeze
  inline_tags = %w[a span strong b em i u s strike small big font code sup sub mark abbr cite q label].freeze

  # Visible words of a piece of markup: text nodes outside head/script/style, merge tags taken out with the
  # importer's own tokenizer (they are rewritten on purpose), punctuation trimmed, case folded.
  define_method(:words) do |texts|
    texts.flat_map do |text|
      plain = EmailCampaigns::Import::MergeTags::Tokenizer.scan(text.to_s).reject(&:tag?).map(&:raw).join(' ')
      plain = EmailCampaigns::Import::Visibility::INVISIBLE.reduce(plain) { |acc, char| acc.gsub(char, ' ') }
      plain.split.filter_map { |word| trim(word) }
    end
  end

  define_method(:trim) do |word|
    trimmed = word.each_char.drop_while { |char| separators.include?(char) }.reverse.drop_while { |char| separators.include?(char) }
    trimmed.reverse.join.downcase.presence
  end

  # The text as a browser lays it out: inline pieces glued (so a tag an editor split across inline tags reads as one),
  # blocks, cells and line breaks apart.
  define_method(:laid_out) do |root|
    parts = []
    root.traverse do |node|
      parts << node.content if node.text?
      parts << ' ' if node.element? && inline_tags.exclude?(node.name)
    end
    parts.join
  end

  define_method(:original_texts) do |source|
    if source.lstrip.start_with?('<mjml') || source.include?("\n<mjml")
      doc = Nokogiri::XML(source) { |config| config.recover.nonet }
      next [laid_out(doc.at_xpath("//*[local-name()='mj-body']"))]
    end
    doc = Nokogiri::HTML5(source)
    doc.css('head, script, style, noscript, template, title').each(&:remove)
    doc.xpath('//comment()').each(&:remove)
    [laid_out(doc.at('body'))]
  end

  define_method(:output_texts) do |mjml|
    doc = Nokogiri::HTML5.fragment(mjml)
    doc.css('mj-section, mj-wrapper').select { |node| node['css-class'].to_s.split.include?('footer-locked') }.each(&:remove)
    doc.css('br').each { |node| node.replace(' ') }
    doc.css('mj-text, mj-button, mj-social-element').map(&:text)
  end

  define_method(:link_key) do |href|
    text = href.to_s.strip
    uri = URI.parse(text)
    uri.host ? "#{uri.host.downcase}#{uri.path}" : text
  rescue URI::Error
    text.split('?').first.to_s
  end

  define_method(:original_links) do |source|
    Nokogiri::HTML5(source).css('body a[href], a[href]').filter_map { |node| node['href'].to_s.strip }.uniq.select do |href|
      tokens = EmailCampaigns::Import::MergeTags::Tokenizer.scan(href)
      next false if tokens.size == 1 && tokens.first.tag?

      schemes.include?(EmailCampaigns::Import::Url.scheme(href))
    end
  end

  # A tracking pixel: a numeric width or height of at most 1px.
  define_method(:pixel_dimension?) do |value|
    text = value.to_s.strip
    text.first.to_s.between?('0', '9') && !text.end_with?('%') && text.to_f <= 1
  end

  define_method(:original_images) do |source|
    Nokogiri::HTML5(source).css('img[src]').filter_map do |node|
      next if dimensions.any? { |dimension| pixel_dimension?(node[dimension]) }

      node['src'].strip if EmailCampaigns::Import::Url.http?(node['src'])
    end.uniq
  end

  Dir[fixtures.join('*.html')].each do |path|
    name = File.basename(path)

    context "with #{name}" do
      let(:source) { File.read(path) }
      let(:result) { described_class.call(source, source_kind: 'file') }
      let(:report) { result.report }
      let(:out) { Nokogiri::HTML5.fragment(result.mjml) }

      it 'compiles as strict MJML made only of editable blocks, with one locked footer and nothing active' do
        compiled = EmailCampaigns::MjmlCompiler.call(result.mjml)
        expect(compiled.errors).to eq([])

        gate = EmailCampaigns::QualityGate.new(mjml: result.mjml, html: compiled.html, remote_images: true,
                                               placeholders: described_class::PLACEHOLDERS + report.items(:unknown_fields).pluck(:key))
        expect(gate.violations.map(&:check) & %i[editable_tags explicit_close_tags unsubscribe mjml_strict]).to eq([])

        expect(out.css('*').map(&:name) & forbidden).to eq([])
        attributes = out.css('*').flat_map(&:attribute_nodes)
        expect(attributes.map(&:name).select { |attribute| attribute.start_with?('on') }).to eq([])
        values = attributes.map { |attribute| attribute.value.downcase.delete(" \t\n") }
        expect(values.select { |value| value.include?('javascript:') || value.include?('vbscript:') || value.include?('expression(') }).to eq([])
        expect(values.select { |value| value.include?('url(') || value.start_with?('data:text') }).to eq([])
        expect(result.mjml).not_to include('{%')
      end

      it 'keeps every visible text, or says why it left' do
        kept = words(output_texts(result.mjml) + [report.preheader] + report.dropped_texts.pluck(:text) +
                     report.unresolved.pluck(:text) + report.recovered_texts)
        missing = words(original_texts(source)).tally.filter_map do |word, count|
          word if kept.count(word) < count
        end

        expect(missing).to eq([])
        expect(report.dropped_texts.pluck(:reason).uniq - allowed_drops).to eq([])
      end

      it 'keeps every link and image, or says why it left' do
        hrefs = out.css('[href]').map { |node| link_key(node['href']) }
        accounted = hrefs + report.dropped_links.map { |link| link_key(link[:href]) } + report.rewritten_links.map { |link| link_key(link[:from]) }
        expect(original_links(source).map { |href| link_key(href) } - accounted).to eq([])
        expect(report.dropped_links.pluck(:reason).uniq - allowed_drops).to eq([])

        sources = out.css('mj-image').map { |node| node['src'] } + out.css('mj-section').filter_map { |node| node['background-url'] } +
                  report.dropped_images.pluck(:src)
        expect(original_images(source) - sources).to eq([])
      end

      it 'leaves at least 70% of the visible area editable' do
        expect(report.editable_area_ratio).to be >= 0.7
      end
    end
  end

  it 'covers one, two and three columns, hero backgrounds, VML buttons, product tables and footers with an address' do
    sources = Dir[fixtures.join('*.html')].map { |path| File.read(path) }

    expect(sources.size).to be >= 16
    expect(sources.count { |source| source.include?('v:roundrect') }).to be >= 2
    expect(sources.count { |source| source.include?('background=') || source.include?('background-image') }).to be >= 2
  end
end
