require 'rails_helper'

# Hostile input to the import engine (#1099): attribute and CSS injection through MJML, template code that would run in
# the sending worker, URL attributes the editor never edits, and the ceilings (elements, depth, time) on every parse.
RSpec.describe EmailCampaigns::Import::Engine, :aggregate_failures do
  def import(input, **)
    described_class.call(input, source_kind: 'paste', **)
  end

  def refusal(input, **)
    import(input, **)
    nil
  rescue EmailCampaigns::Import::Error => e
    e.code
  end

  def mjml(column)
    "<mjml><mj-body><mj-section><mj-column>#{column}</mj-column></mj-section></mj-body></mjml>"
  end

  def body(result)
    Nokogiri::HTML5.fragment(result.mjml).css('mj-section').reject { |section| section['css-class'].to_s.include?('footer-locked') }
  end

  def attribute_names(result)
    out = Nokogiri::HTML5.fragment(result.mjml)
    inner = out.css('mj-text, mj-button, mj-social').flat_map { |node| Nokogiri::HTML5.fragment(node.inner_html).css('*') }
    (out.css('*').to_a + inner).flat_map(&:attribute_nodes).map(&:name)
  end

  def codes(result)
    result.report.to_h[:warnings].pluck(:code)
  end

  describe 'colors and CSS values of MJML attributes' do
    it 'never lets a color break out of the style of a link, in a text block or a navbar' do
      result = import(mjml(%(<mj-text color='y" onclick="alert(2)'><a href="https://a.example.com">link</a> texto</mj-text>) +
                           %(<mj-navbar><mj-navbar-link color='x" onmouseover="alert(1)' href="https://b.example.com">Oi</mj-navbar-link></mj-navbar>)))

      expect(attribute_names(result).select { |name| name.start_with?('on') }).to eq([])
      expect(result.mjml).not_to include('alert(')
      expect(result.mjml).to include('https://a.example.com', 'https://b.example.com', 'texto', 'Oi')
    end

    it 'keeps only a normalized color and a numeric line height, dropping CSS smuggled into them' do
      result = import(<<~MJML)
        <mjml><mj-body background-color="red;background:url(https://evil.example/b.png)">
          <mj-section background-color="red;background-image:url(https://evil.example/t.png)">
            <mj-column background-color="blue;background:url(https://evil.example/c.png)">
              <mj-text color="red;background:url(https://evil.example/x)" line-height="1;background:url(https://evil.example/l.png)">oi <a href="https://b.example.com">l</a></mj-text>
              <mj-button href="https://c.example.com" background-color='#ff0000" onclick="x' color="#ffffff">Comprar</mj-button>
            </mj-column>
          </mj-section>
        </mj-body></mjml>
      MJML

      expect(result.mjml).not_to include('evil.example', 'onclick')
      expect(EmailCampaigns::MjmlCompiler.call(result.mjml).errors).to eq([])
      expect(codes(result)).to include(:unsafe_css_removed)
    end
  end

  it 'drops the URL attributes the editor never edits, so no address escapes the image list' do
    result = import(mjml('<mj-image src="https://ok.example.com/a.png" srcset="http://169.254.169.254/latest 1x" alt="a"/>' \
                         '<mj-carousel><mj-carousel-image src="https://ok.example.com/b.png" thumbnails-src="http://10.0.0.1/t.png"/></mj-carousel>' \
                         '<mj-accordion icon-wrapped-url="http://10.0.0.2/i.png" icon-unwrapped-url="http://10.0.0.3/i.png">' \
                         '<mj-accordion-element><mj-accordion-title>T</mj-accordion-title><mj-accordion-text>X</mj-accordion-text>' \
                         '</mj-accordion-element></mj-accordion>'))

    expect(result.mjml).not_to include('169.254.169.254', '10.0.0.1', '10.0.0.2', '10.0.0.3', 'srcset', 'thumbnails-src')
    expect(result.report.images.pluck(:src)).to contain_exactly('https://ok.example.com/a.png', 'https://ok.example.com/b.png')
  end

  describe 'template code' do
    it 'leaves no template statement or unclosed output tag that the sending worker would run' do
      long = 'a' * 320
      html = "<table width=\"600\"><tr><td><p>Antes {% for i in (1..2000000000) #{long} %}X{% endfor #{long} %} depois</p>" \
             "<p>Use {{ para abrir</p><p>Oi {{ nome }}</p><img src=\"https://ok.example.com/a.png\" alt=\"{% raw #{long} %}\"></td></tr></table>"
      result = import(html)

      expect(result.mjml).not_to include('{%')
      expect(result.mjml.scan('{{').size).to eq(result.mjml.scan('}}').size)
      expect(result.mjml).to include('Antes', 'depois', '{{ nome }}', 'Use')
      expect(result.report.dropped_texts.pluck(:reason)).to include(:template)
      expect(codes(result)).to include(:template_code_removed)
    end

    it 'catches template code an editor split across inline tags, which only meets again in the output' do
      result = import('<table width="600"><tr><td><p>Oi <span>{</span><span>% for i in (1..2000000000) %}</span>X' \
                      '<span>{</span><span>% endfor %}</span> fim</p></td></tr></table>')

      expect(result.mjml).not_to include('{%')
      expect(result.mjml).to include('Oi', 'X', 'fim')
    end

    it 'drops template code written in MJML attributes' do
      result = import(mjml('<mj-image src="https://ok.example.com/a.png" alt="ok" title="{% for i in (1..9) %}x{% endfor %}"/>'))

      expect(result.mjml).not_to include('{%')
    end
  end

  describe 'ceilings' do
    it 'counts the HTML inside MJML blocks against the element ceiling' do
      links = '<p><a href="https://a.example.com/x" style="background-color:#ff0000">b</a></p>' * 2_600

      expect(refusal(mjml("<mj-text>#{links}</mj-text>"))).to eq(:too_many_nodes)
    end

    it 'refuses HTML nested beyond the parser limit, in a page or inside an MJML block, with the depth code' do
      deep = "#{'<span>' * 450}x#{'</span>' * 450}"

      expect(refusal(deep)).to eq(:too_deep)
      expect(refusal(mjml("<mj-text>#{deep}</mj-text>"))).to eq(:too_deep)
      expect(refusal(mjml("<mj-text>#{'<span>' * 45}x#{'</span>' * 45}</mj-text>"))).to eq(:too_deep)
    end

    it 'stops the whole conversion past its time budget' do
      ticks = 0
      clock = -> { ticks += 1 }
      budget = EmailCampaigns::Import::Budget.new(seconds: 50, clock: clock)

      expect(refusal("<table width=\"600\"><tr><td>#{'<p>texto</p>' * 200}</td></tr></table>", budget: budget)).to eq(:too_slow)
    end

    it 'stays fast with many button-like links in one cell' do
      links = '<p><a href="https://a.example.com/x" style="background-color:#ff0000">b</a></p>' * 1_600
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      import("<table width=\"600\"><tr><td>#{links}</td></tr></table>")

      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
    end
  end
end
