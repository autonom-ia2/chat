require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::Sanitizer, :aggregate_failures do
  def wrap(body)
    "<mjml><mj-body><mj-section><mj-column>#{body}</mj-column></mj-section>" \
      '<mj-section css-class="footer-locked"><mj-column><mj-text><a href="{{ unsubscribe_url }}">Sair</a></mj-text></mj-column></mj-section>' \
      '</mj-body></mjml>'
  end

  it 'stores canonical MJML: explicit close tags and head defaults resolved into the body' do
    mjml = '<mjml><mj-head><mj-attributes><mj-all font-family="Arial" /><mj-text line-height="1.6" />' \
           '<mj-image padding="0" /></mj-attributes></mj-head>' \
           "<mj-body><mj-section><mj-column><mj-image src=\"https://x.test/a.png\" /><mj-spacer height=\"8px\" />\n" \
           '<mj-text>Oi<br/>tudo bem?</mj-text></mj-column></mj-section></mj-body></mjml>'

    out = described_class.new(mjml).perform

    expect(out).not_to include('mj-attributes')
    expect(out).to include('<mj-image src="https://x.test/a.png" padding="0"></mj-image><mj-spacer height="8px"></mj-spacer>')
    expect(out).to include('<mj-text font-family="Arial" line-height="1.6">Oi<br/>tudo bem?</mj-text>')
    expect(described_class.new(out).perform).to eq(out)
  end

  it 'brings back the defaults of a head corrupted by the old editor' do
    mjml = '<mjml><mj-head><mj-attributes><mj-all font-family="Arial"><mj-text color="#111" line-height="1.6">' \
           '<mj-button font-family="Arial"></mj-button></mj-text></mj-all></mj-attributes></mj-head>' \
           '<mj-body><mj-section css-class="footer-locked"><mj-column><mj-text><a href="{{ unsubscribe_url }}">Sair</a></mj-text>' \
           '</mj-column></mj-section></mj-body></mjml>'

    out = described_class.new(mjml).perform

    expect(out).not_to include('mj-attributes')
    expect(out).to include('<mj-text font-family="Arial" color="#111" line-height="1.6"><a href="{{ unsubscribe_url }}">Sair</a></mj-text>')
  end

  it 'strips a script that reassembles after the first pass' do
    out = described_class.new(wrap('<mj-text>a<scr<script>x</script>ipt>alert(1)</script>b</mj-text>')).perform

    expect(out.downcase).not_to include('<script')
  end

  it 'turns web-search citations into links without the openai utm' do
    text = 'Comparativo no WhatsApp. ([viagem.hub2you.ai](https://viagem.hub2you.ai/?utm_source=openai)) ' \
           'Veja ([site.com](https://site.com/p?cit=502&utm_source=openai&def=x)).'

    out = described_class.new(wrap("<mj-text>#{text}</mj-text>")).perform

    expect(out).to include('Comparativo no WhatsApp. (<a href="https://viagem.hub2you.ai/">viagem.hub2you.ai</a>)')
    expect(out).to include('Veja (<a href="https://site.com/p?cit=502&amp;def=x">site.com</a>).')
    expect(out).not_to include('utm_source=openai')
    expect(out).not_to include('](')
  end

  it 'keeps other query params and leaves non-http markdown untouched' do
    text = '[ok](https://a.test/?utm_source=news) e [mau](javascript:alert(1)) e [x] (y)'

    out = described_class.new(wrap("<mj-text>#{text}</mj-text>")).perform

    expect(out).to include('<a href="https://a.test/?utm_source=news">ok</a>')
    expect(out).to include('[mau](javascript:alert(1))')
    expect(out).not_to include('href="javascript')
    expect(out).to include('[x] (y)')
  end

  it 'still neutralizes unsafe hrefs and strips scripts' do
    body = '<mj-button href="java&#x09;script:alert(1)">Clique</mj-button>' \
           '<mj-text><a href="javascript&colon;alert(1)" onclick="x()">a</a><script>alert(1)</script></mj-text>'

    out = described_class.new(wrap(body)).perform

    expect(out).to include('<mj-button href="#">Clique</mj-button>')
    expect(out).to include('<a href="#">a</a>')
    expect(out).not_to include('<script', 'onclick', 'javascript')
  end

  it 'appends a generic locked footer without any hardcoded brand' do
    out = described_class.new('<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>').perform

    expect(out).to include('footer-locked', '{{ unsubscribe_url }}')
    expect(out).not_to include('hub2you', 'Hub2you', 'Av. Exemplo')
    expect(out.index('footer-locked')).to be < out.index('</mj-body>')
    expect(described_class.new(out).perform).to eq(out)
  end

  describe 'parser-based allowlist (#1104)' do
    def clean(body)
      described_class.new(wrap(body)).perform
    end

    def safe!(out)
      expect(out.downcase).not_to include('<script', 'javascript', 'vbscript', 'onerror', 'onload', 'onclick', '<iframe', '<svg', '<math',
                                          'expression', 'data:text')
    end

    it 'blocks script schemes hidden by entities, case, whitespace and double encoding' do
      ['&#106;&#97;vascript:alert(1)', '&#x6A;avascript:alert(1)', '&#0000106avascript:alert(1)', 'javascript&colon;alert(1)',
       'java&Tab;script:alert(1)', 'java&NewLine;script:alert(1)', 'JaVaScRiPt:alert(1)', "java\nscript:alert(1)",
       '&amp;#106;avascript:alert(1)', 'VBScript:msgbox(1)', 'data:text/html;base64,PHNjcmlwdD4='].each do |href|
        out = clean(%(<mj-button href="#{href}">Ir</mj-button><mj-text><a href="#{href}">a</a></mj-text>))

        expect(out).to include('<mj-button href="#">Ir</mj-button>', '<a href="#">a</a>')
        safe!(out)
      end
    end

    it 'blocks a script scheme behind control characters in HTML' do
      out = clean(%(<mj-text><a href=" \u0001java\u0002script:alert(1)">a</a><img src="\tjavascript:alert(1)"></mj-text>))

      expect(out).to include('<a href="#">a</a>', '<img src="#">')
      safe!(out)
    end

    it 'keeps safe schemes, relative links, anchors and Liquid placeholders exactly as written' do
      body = '<mj-image src="https://x.test/a.png?w=1&amp;h=2"></mj-image><mj-button href="{{ link_oferta }}">Ir</mj-button>' \
             '<mj-text><a href="mailto:oi@loja.test">e-mail</a> <a href="tel:+5511999999999">tel</a> <a href="/p?x=1">rel</a> ' \
             '<a href="#topo">topo</a> Olá {{ nome }}, {% if pontos > 10 %}parabéns{% endif %}&nbsp;<br/>' \
             '<span style="color:#111;background-image:url(https://x.test/bg.png)">fim</span></mj-text>'

      expect(clean(body)).to include(body)
    end

    it 'drops inline event handlers in any case, quoted or not, in MJML and in HTML' do
      out = clean('<mj-image src="https://x.test/a.png" onload="x()"></mj-image>' \
                  "<mj-text><img src=\"https://x.test/b.png\" OnError=alert(1)><b onmouseover='x()'>b</b></mj-text>")

      expect(out).to include('<mj-image src="https://x.test/a.png"></mj-image>', '<img src="https://x.test/b.png">', '<b>b</b>')
      expect(out.downcase).not_to include('onmouseover')
      safe!(out)
    end

    it 'never lets nested or split tags reassemble into a script' do
      ['<scr<script>ipt>alert(1)</script>', '<<script>script>alert(1)<</script>/script>', '<scr<iframe></iframe>ipt>alert(1)</script>',
       '<SCRIPT SRC=//x.test/x.js></SCRIPT>', '<scr<script>x</script>ipt src=//x.test/x.js></scr<script>x</script>ipt>'].each do |payload|
        out = clean("<mj-text>a#{payload}b</mj-text>")

        safe!(out)
        expect(out).to include('<mj-text>a')
      end
    end

    it 'drops SVG and MathML, including mutation tricks' do
      svg = clean('<mj-text>antes<svg onload=alert(1)><script>alert(1)</script><a xlink:href="javascript:alert(1)">x</a></svg> depois</mj-text>')
      math = clean('<mj-text><math><mtext><table><mglyph><style><img src=x onerror=alert(1)></style></mglyph></table></mtext></math></mj-text>')

      expect(svg).to include('<mj-text>antes depois</mj-text>')
      safe!(svg)
      safe!(math)
    end

    it 'drops dangerous CSS from inline styles and keeps the other declarations' do
      out = clean('<mj-text><span style="color:#111;width:expression(alert(1))">a</span>' \
                  '<span style="background:url(javascript:alert(1));font-weight:700">b</span>' \
                  '<span style="background:u\\72l(javascript:alert(1))">c</span><span style="behavior:url(x.htc)">d</span></mj-text>')

      expect(out).to include('<span style="color:#111">a</span>', '<span style="font-weight:700">b</span>', '<span>c</span>',
                             '<span>d</span>')
      expect(out).not_to include('x.htc', '\\72')
      safe!(out)
    end

    it 'removes active elements from the MJML tree, comments, raw blocks and head text' do
      out = described_class.new(
        '<mjml><mj-head><mj-title>T<script>alert(1)</script></mj-title><mj-style>.a{color:red}</style><script>alert(1)</script></mj-style>' \
        '<mj-preview>P<img src=x onerror=alert(1)></mj-preview></mj-head><mj-body><!--[if mso]><script>alert(1)</script><![endif]-->' \
        '<mj-section><mj-column><script>alert(1)</script><iframe src="https://x.test"></iframe><mj-text>Oi' \
        '<!--[if mso]><script>alert(1)</script><![endif]--></mj-text><mj-raw><object data="x.swf"></object><form action="javascript:x()">' \
        '<input></form><embed src="x"><base href="https://x.test"><table><tr><td>raw</td></tr></table></mj-raw>' \
        '<mj-text><a href="{{ unsubscribe_url }}">Sair</a></mj-text></mj-column></mj-section></mj-body></mjml>'
      ).perform

      expect(out).to include('<mj-title>T</mj-title>', '<mj-text>Oi</mj-text>', '<table><tbody><tr><td>raw</td></tr></tbody></table>')
      expect(out.downcase).not_to include('<object', '<form', '<embed', '<base', '</style>', 'x.swf')
      safe!(out)
    end

    it 'drops content nested deeper than the parser reads instead of keeping it unchecked' do
      out = clean("<mj-text>#{'<div>' * 500}<script>alert(1)</script></mj-text>")

      expect(out).to include('<mj-text></mj-text>')
      safe!(out)
    end

    it 'repairs and cleans MJML that is not well-formed instead of keeping it as written' do
      out = described_class.new('<mjml><mj-body><mj-section><mj-column><mj-image src="javascript:alert(1)">' \
                                '<mj-text>x<script>alert(1)</script></mj-text></mj-column></mj-section></mj-body></mjml>').perform

      expect(out).to include('src="#"', 'footer-locked', '{{ unsubscribe_url }}')
      safe!(out)
      expect(described_class.new(out).perform).to eq(out)
    end
  end
end
