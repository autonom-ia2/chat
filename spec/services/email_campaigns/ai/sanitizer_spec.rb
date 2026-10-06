require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::Sanitizer, :aggregate_failures do
  def wrap(body)
    "<mjml><mj-body><mj-section><mj-column>#{body}</mj-column></mj-section>" \
      '<mj-section css-class="footer-locked"><mj-column><mj-text><a href="{{ unsubscribe_url }}">Sair</a></mj-text></mj-column></mj-section>' \
      '</mj-body></mjml>'
  end

  it 'stores canonical MJML: explicit close tags and a flat mj-attributes' do
    mjml = '<mjml><mj-head><mj-attributes><mj-all font-family="Arial" /><mj-text line-height="1.6" />' \
           '<mj-image padding="0" /></mj-attributes></mj-head>' \
           "<mj-body><mj-section><mj-column><mj-image src=\"https://x.test/a.png\" /><mj-spacer height=\"8px\" />\n" \
           '<mj-text>Oi<br/>tudo bem?</mj-text></mj-column></mj-section></mj-body></mjml>'

    out = described_class.new(mjml).perform

    expect(out).to include('<mj-attributes><mj-all font-family="Arial"></mj-all><mj-text line-height="1.6"></mj-text>' \
                           '<mj-image padding="0"></mj-image></mj-attributes>')
    expect(out).to include('<mj-image src="https://x.test/a.png"></mj-image><mj-spacer height="8px"></mj-spacer>')
    expect(out).to include('<mj-text>Oi<br/>tudo bem?</mj-text>')
    expect(described_class.new(out).perform).to eq(out)
  end

  it 'repairs a head corrupted by the old editor' do
    mjml = '<mjml><mj-head><mj-attributes><mj-all font-family="Arial"><mj-text color="#111" line-height="1.6">' \
           '<mj-button font-family="Arial"></mj-button></mj-text></mj-all></mj-attributes></mj-head>' \
           '<mj-body><mj-section css-class="footer-locked"><mj-column><mj-text><a href="{{ unsubscribe_url }}">Sair</a></mj-text>' \
           '</mj-column></mj-section></mj-body></mjml>'

    out = described_class.new(mjml).perform

    expect(out).to include('<mj-attributes><mj-all font-family="Arial"></mj-all><mj-text color="#111" line-height="1.6"></mj-text>' \
                           '<mj-button font-family="Arial"></mj-button></mj-attributes>')
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
end
