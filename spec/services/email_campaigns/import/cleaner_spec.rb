require 'rails_helper'

# Sanitizer + Outlook branches + hidden text + links, run together as the importer runs them (EmailCampaigns::Import::Cleaner).
RSpec.describe EmailCampaigns::Import::Cleaner, :aggregate_failures do
  let(:report) { EmailCampaigns::Import::Report.new(source_kind: 'paste') }

  def clean(html, base_url: nil)
    doc = Nokogiri::HTML5("<html><head></head><body>#{html}</body></html>")
    described_class.call(doc.root, report, base_url: base_url).inner_html.strip
  end

  def warning(code)
    report.to_h[:warnings].find { |entry| entry[:code] == code }
  end

  it 'keeps only allowed elements and attributes, dropping active content and unwrapping the unknown' do
    out = clean('<script>alert(1)</script><form action="x"><input name="a"><button>Confirmar</button></form>' \
                '<iframe src="https://v.example.com"></iframe><object data="x"></object><embed src="y"><svg onload="a()"><circle/></svg>' \
                '<amp-img src="a.jpg"></amp-img><o:p>x</o:p>' \
                '<custom-box class="a" id="b" data-x="1"><p onclick="x()" class="c">Texto</p></custom-box>')

    expect(out).to eq('<p>Texto</p>')
    expect(warning(:unsafe_removed)[:items]).to include('script', 'form', 'iframe', 'object', 'embed', 'svg')
    expect(report.dropped_texts).to include({ text: 'Confirmar', reason: :unsafe })
  end

  it 'counts the dangerous parts of the head it drops' do
    doc = Nokogiri::HTML5('<html><head><meta http-equiv="refresh" content="0;url=x"><base href="https://x.example.net/">' \
                          '<link rel="stylesheet" href="y.css"><script>z()</script></head><body><p>Oi</p></body></html>')
    described_class.call(doc.root, report)

    expect(warning(:unsafe_removed)[:items]).to contain_exactly('meta', 'base', 'script')
    expect(doc.root.to_html).not_to include('refresh', 'base', 'y.css', 'z()')
  end

  it 'filters inline CSS by property and value, turning a background image into an internal marker' do
    out = clean('<table><tr><td background="https://img.example.com/fundo.jpg" style="color:#fff;width:expression(alert(1));' \
                'behavior:url(x.htc);background:url(\'https://img.example.com/fundo.jpg\') center #1F3A5F;position:absolute">Oi</td></tr></table>' \
                '<div style="background-image:url(javascript:alert(1))">x</div>')

    expect(out).to include('<td style="color:#fff;background-color:#1f3a5f" data-import-bg="https://img.example.com/fundo.jpg">Oi</td>')
    expect(out).to include('<div>x</div>')
    expect(warning(:unsafe_css_removed)[:count]).to be >= 2
  end

  it 'keeps the non-Outlook branch of conditional comments and rebuilds a VML-only button' do
    out = clean('<!--[if mso]><table><tr><td>Só Outlook</td></tr></table><![endif]-->' \
                '<!--[if !mso]><!-- --><p>Para todos</p><!--<![endif]-->' \
                '<div><!--[if mso]><v:roundrect href="https://loja.example.com/ofertas" fillcolor="#F97316" style="height:48px;">' \
                '<w:anchorlock/><center style="color:#ffffff;">Ver ofertas</center></v:roundrect><![endif]--></div>')

    expect(out).not_to include('Só Outlook', '<!--')
    expect(out).to include('<p>Para todos</p>')
    expect(out).to include('href="https://loja.example.com/ofertas"', '>Ver ofertas</a>', 'background-color:#f97316')
    expect(warning(:vml_button_recovered)[:count]).to eq(1)
    expect(warning(:outlook_only)).to be_present
  end

  it 'does not duplicate a VML button that also exists for every other client' do
    out = clean('<td><!--[if mso]><v:roundrect href="https://a.example.com/x" fillcolor="#000"><center>Ir</center></v:roundrect><![endif]-->' \
                '<!--[if !mso]><!-- -->' \
                '<a href="https://a.example.com/x?utm_source=y" style="background-color:#000;color:#fff">Ir</a><!--<![endif]--></td>')

    expect(out.scan('Ir</a>').size).to eq(1)
    expect(warning(:vml_button_recovered)).to be_nil
  end

  it 'removes hidden text — display:none, tiny or zero font, text the color of its background, mso-hide — and keeps the preheader' do
    out = clean('<div style="display:none;max-height:0;overflow:hidden">Resumo do e-mail &#8199;&#65279;</div>' \
                '<p>Visível</p><p style="display:none">Escondido</p><span style="mso-hide:all">Outlook</span>' \
                '<div style="font-size:0">  <span style="font-size:16px">Coluna</span></div><p style="font-size:0px">Zero</p>' \
                '<table bgcolor="#ffffff"><tr><td style="color:#ffffff">Branco no branco</td></tr></table>' \
                '<div style="max-height:0px;overflow:hidden">Depois do visível</div>')

    expect(report.preheader).to eq('Resumo do e-mail')
    expect(out).to include('Visível', 'Coluna')
    expect(out).not_to include('Escondido', 'Outlook', 'Zero', 'Branco no branco', 'Depois do visível', 'Resumo')
    expect(report.dropped_texts.pluck(:text)).to include('Escondido', 'Outlook', 'Zero', 'Branco no branco', 'Depois do visível')
    expect(warning(:hidden_text_removed)[:count]).to eq(5)
  end

  it 'removes tracking pixels by size or visibility' do
    out = clean('<p>Oi</p><img src="https://t.example.com/open.gif" width="1" height="1" alt="">' \
                '<img src="https://t.example.com/b.gif" width="0" height="0"><img src="https://t.example.com/c.gif" style="display:none">' \
                '<img src="https://t.example.com/d.gif" style="width:1px;height:1px">' \
                '<img src="https://img.example.com/logo.png" width="120" alt="Logo">')

    expect(out).to eq('<p>Oi</p><img src="https://img.example.com/logo.png" width="120" alt="Logo">')
    expect(warning(:tracking_removed)[:count]).to eq(4)
  end

  it 'keeps only http, https, mailto and tel links, keeping the text of the links it removes' do
    out = clean('<a href="javascript:alert(1)">A</a><a href="  JaVaScRiPt:alert(5)">B</a><a href="java&#x09;script:alert(6)">C</a>' \
                '<a href="data:text/html;base64,PHNjcmlwdD4=">D</a><a href="vbscript:x">E</a><a href="/promocao">F</a><a href="#">G</a>' \
                '<a href="mailto:contato@loja.example.com?subject=Quero">H</a><a href="tel:+5500000000">I</a>' \
                '<a href="//cdn.example.com/x">J</a><a href="https://loja.example.com/x">K</a>')

    expect(out).to eq('ABCDEFG<a href="mailto:contato@loja.example.com?subject=Quero">H</a><a href="tel:+5500000000">I</a>' \
                      '<a href="https://cdn.example.com/x">J</a><a href="https://loja.example.com/x">K</a>')
    expect(report.dropped_links.pluck(:reason).tally).to eq({ unsafe: 5, relative: 2 })
  end

  it 'resolves relative links and images against the page address when there is one' do
    out = clean('<a href="/promocao">F</a><img src="img/logo.png" alt="Logo">', base_url: 'https://loja.example.com/emails/abril.html')

    expect(out).to eq('<a href="https://loja.example.com/promocao">F</a><img src="https://loja.example.com/emails/img/logo.png" alt="Logo">')
  end

  it 'unwraps a click redirect only when its destination is a trusted absolute URL, keeping the UTM, and never fetches it' do
    out = clean('<a href="https://r.mail.example.com/mk/cl/f/Ab?u=https%3A%2F%2Floja.example.com%2Fdicas&amp;utm_source=news">A</a>' \
                '<a href="https://r.mail.example.com/c?url=nada-aqui">B</a>' \
                '<a href="https://loja.example.com/painel?_hsenc=p2A&amp;_hsmi=1&amp;utm_medium=email">C</a>')

    expect(out).to eq('<a href="https://loja.example.com/dicas?utm_source=news">A</a><a href="https://r.mail.example.com/c?url=nada-aqui">B</a>' \
                      '<a href="https://loja.example.com/painel?utm_medium=email">C</a>')
    expect(report.rewritten_links.first).to eq({ from: 'https://r.mail.example.com/mk/cl/f/Ab?u=https%3A%2F%2Floja.example.com%2Fdicas&utm_source=news',
                                                 to: 'https://loja.example.com/dicas?utm_source=news' })
    expect(warning(:redirect_kept)[:count]).to eq(1)
  end

  it 'marks images it cannot use — relative without an address, SVG — and keeps data and plain-http images for copying' do
    out = clean('<img src="/imagens/logo.png" alt="Logo"><img src="data:image/svg+xml;base64,PHN2Zz4=" alt="Vetor">' \
                '<img src="data:image/png;base64,iVBORw0KGgo=" alt="Embutida" width="40"><img src="http://sem-tls.example.org/b.jpg" alt="B">')

    expect(out).to eq('<img alt="Logo" data-import-missing="1"><img alt="Vetor" data-import-missing="1">' \
                      '<img src="data:image/png;base64,iVBORw0KGgo=" alt="Embutida" width="40"><img src="http://sem-tls.example.org/b.jpg" alt="B">')
    expect(warning(:image_missing)[:count]).to eq(2)
  end

  it 'turns a video with a poster into a linked image' do
    out = clean('<video src="https://v.example.com/a.mp4" poster="https://v.example.com/p.jpg" controls></video>')

    expect(out).to eq('<a href="https://v.example.com/a.mp4"><img src="https://v.example.com/p.jpg" alt=""></a>')
    expect(warning(:video_as_image)[:count]).to eq(1)
  end
end
