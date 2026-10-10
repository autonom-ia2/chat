require 'rails_helper'

RSpec.describe EmailCampaigns::Import::Converter, :aggregate_failures do
  let(:report) { EmailCampaigns::Import::Report.new(source_kind: 'paste') }

  def document(html)
    doc = Nokogiri::HTML5("<html><head></head><body>#{html}</body></html>")
    body = EmailCampaigns::Import::Cleaner.call(doc.root, report)
    described_class.call(body, report)
  end

  def mjml(html)
    Nokogiri::HTML5.fragment(EmailCampaigns::Import::Emitter.call(document(html)))
  end

  def email(rows, width: 600, outer: '#edeff2', inner: '#ffffff')
    %(<table width="100%" bgcolor="#{outer}"><tr><td align="center">) +
      %(<table width="#{width}" bgcolor="#{inner}">#{rows}</table></td></tr></table>)
  end

  it 'makes the 600px container the body, each row a section and each cell a column' do
    out = mjml(email('<tr><td style="padding:24px"><p>Um</p></td></tr>' \
                     '<tr><td width="50%"><p>Esquerda</p></td><td width="50%"><p>Direita</p></td></tr>'))

    expect(out.at('mj-body')['width']).to eq('600px')
    expect(out.at('mj-body')['background-color']).to eq('#edeff2')
    expect(out.css('mj-section').size).to eq(2)
    expect(out.css('mj-section').first['padding']).to eq('24px 24px 24px 24px')
    expect(out.css('mj-section').map { |section| section['background-color'] }).to eq(%w[#ffffff #ffffff])
    expect(out.css('mj-section')[1].css('mj-column').map { |column| column['width'] }).to eq(%w[50% 50%])
  end

  it 'groups running text into one mj-text, carries the cell style down and splits only where the style changes' do
    out = mjml(email('<tr><td style="font-family:Georgia;font-size:15px;color:#555555;line-height:22px" align="center">' \
                     '<h1 style="font-size:26px;color:#202020">Olá, {{ nome }}!</h1><p>Primeiro <strong>parágrafo</strong>.</p>' \
                     '<p>Segundo com <a href="https://loja.example.com/x" style="color:#007c89">link</a> ' \
                     'e <span style="color:#990000">cor</span>.</p>' \
                     '<ul><li>Item 1</li><li>Item 2</li></ul></td></tr>'))
    texts = out.css('mj-text')

    expect(texts.size).to eq(2)
    expect(texts.first['font-size']).to eq('26px')
    expect(texts.first['font-weight']).to eq('700')
    expect(texts.first.inner_html).to eq('Olá, {{ nome }}!')
    expect(texts.last.attributes.transform_values(&:value)).to include('font-size' => '15px', 'color' => '#555555', 'align' => 'center',
                                                                       'line-height' => '22px')
    expect(texts.map { |text| text['font-family'] }.uniq).to eq([EmailCampaigns::Import::WebFonts::SERIF])
    expect(texts.last.inner_html).to eq('Primeiro <strong>parágrafo</strong>.<br><br>Segundo com ' \
                                        '<a href="https://loja.example.com/x" style="color:#007c89;text-decoration:underline">link</a> e ' \
                                        '<span style="color:#990000">cor</span>.<br><br>• Item 1<br>• Item 2')
  end

  it 'turns linked and plain images, buttons, rules and spacers into their blocks' do
    out = mjml(email('<tr><td><a href="https://loja.example.com"><img src="https://img.example.com/logo.png" width="150" alt="Logo"></a>' \
                     '<table align="center"><tr><td bgcolor="#F97316" style="border-radius:4px;padding:12px 24px">' \
                     '<a href="https://loja.example.com/comprar" style="color:#ffffff;font-size:16px;font-weight:bold">Comprar</a>' \
                     '</td></tr></table>' \
                     '<hr style="border-top:1px solid #dddddd"><div style="height:32px;line-height:32px">&nbsp;</div>' \
                     '<img src="https://img.example.com/foto.jpg" alt="Foto"></td></tr>'))

    expect(out.css('mj-column > *').map(&:name)).to eq(%w[mj-image mj-button mj-divider mj-spacer mj-image])
    expect(out.at('mj-image').attributes.transform_values(&:value))
      .to include('src' => 'https://img.example.com/logo.png', 'href' => 'https://loja.example.com', 'width' => '150px', 'alt' => 'Logo')
    expect(out.at('mj-button').attributes.transform_values(&:value))
      .to include('href' => 'https://loja.example.com/comprar', 'background-color' => '#f97316', 'color' => '#ffffff',
                  'inner-padding' => '12px 24px 12px 24px', 'border-radius' => '4px', 'font-weight' => '700')
    expect(out.at('mj-button').text).to eq('Comprar')
    expect(out.at('mj-spacer')['height']).to eq('32px')
  end

  it 'turns a cell with a background image into a section that keeps the text over it editable' do
    out = mjml(email('<tr><td background="https://img.example.com/banner.jpg" bgcolor="#1F3A5F" height="260">' \
                     '<div style="color:#ffffff;font-size:28px">Você está convidado!</div></td></tr>'))
    section = out.at('mj-section')

    expect(section['background-url']).to eq('https://img.example.com/banner.jpg')
    expect(section['background-color']).to eq('#1f3a5f')
    expect(section.at('mj-text').text).to eq('Você está convidado!')
  end

  it 'keeps three or more columns side by side on desktop, stacking on the phone as MJML columns do' do
    cell = ->(text) { "<td width=\"33%\" align=\"center\"><img src=\"https://img.example.com/#{text}.png\" width=\"48\" alt=\"\">#{text}</td>" }
    out = mjml(email("<tr><td><table width=\"100%\"><tr>#{%w[data local hora].map(&cell).join}</tr></table></td></tr>"))

    expect(out.css('mj-section').size).to eq(1)
    expect(out.css('mj-column').size).to eq(3)
    expect(out.css('mj-group')).to be_empty
    expect(out.css('mj-column').map { |column| column['width'] }).to eq(%w[33.33% 33.33% 33.34%])
  end

  it 'reads side-by-side blocks, floated tables and grids as columns' do
    inline = mjml('<div style="max-width:600px"><div style="display:inline-block;width:50%">A</div>' \
                  '<div style="display:inline-block;width:50%">B</div></div>')
    floated = mjml('<table width="600"><tr><td>' \
                   '<table align="left" width="176"><tr><td><img src="https://i.example.com/a.jpg" alt="A"></td></tr></table>' \
                   '<table align="right" width="352"><tr><td>Texto ao lado</td></tr></table></td></tr></table>')

    expect(inline.css('mj-column').map { |column| column.text.strip }).to eq(%w[A B])
    expect(floated.css('mj-column').map { |column| column['width'] }).to eq(%w[33.33% 66.67%])
  end

  it 'writes a simple data table as lines of text and leaves a complex one for later, as a marked image' do
    out = mjml(email('<tr><td><table><tr><td>Serviço 1</td><td>R$ 19,99</td></tr><tr><td>Serviço 2</td><td>R$ 9,99</td></tr></table>' \
                     '<table><tr><td>A</td><td>B</td><td>C</td><td>D</td><td>E</td></tr>' \
                     '<tr><td>1</td><td>2</td><td>3</td><td>4</td><td>5</td></tr></table></td></tr>'))

    expect(out.at('mj-text').inner_html).to eq('Serviço 1 — R$ 19,99<br>Serviço 2 — R$ 9,99')
    placeholder = out.css('mj-image').last
    expect(placeholder['css-class']).to eq('import-unresolved')
    expect(placeholder['src']).to eq(EmailCampaigns::Import::Placeholders::UNRESOLVED_SRC)
    expect(placeholder['alt']).to eq('A B C D E 1 2 3 4 5')
    expect(report.unresolved.first).to include(id: placeholder['title'], text: 'A B C D E 1 2 3 4 5')
    expect(report.unresolved.first[:html]).to include('<td>E</td>')
  end

  it 'keeps a placeholder where an image could not be used' do
    out = mjml(email('<tr><td><img src="/so-no-servidor.png" alt="Logo" width="120"></td></tr>'))

    expect(out.at('mj-image').attributes.transform_values(&:value))
      .to include('src' => EmailCampaigns::Import::Placeholders::MISSING_SRC, 'alt' => 'Logo', 'css-class' => 'import-missing')
  end

  it 'reads a two-row table of titles and text as columns, not as a table of data' do
    out = mjml(email('<tr><td><table><tr><td><strong>Loja Centro</strong></td><td><strong>Loja Sul</strong></td></tr>' \
                     '<tr><td>Rua A, 100</td><td>Av. B, 200</td></tr></table></td></tr>'))

    expect(out.to_html).not_to include('Loja Centro — Loja Sul')
    expect(report.count(:table_as_text)).to eq(0)
  end

  it 'links the image of a card whose link wraps the image and the text' do
    out = mjml(email('<tr><td><a href="https://loja.example.com/p1"><img src="https://img.example.com/p1.jpg" alt="P1" width="200">' \
                     '<p>Produto 1</p></a></td></tr>'))

    expect(out.at('mj-image')['href']).to eq('https://loja.example.com/p1')
    expect(out.at('mj-text').inner_html).to include('href="https://loja.example.com/p1"')
  end
end
