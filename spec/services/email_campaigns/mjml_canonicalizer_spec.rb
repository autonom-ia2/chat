require 'rails_helper'

RSpec.describe EmailCampaigns::MjmlCanonicalizer, :aggregate_failures do
  # Same real AI e-mail (anonymized) used by the editor spec, so front and back agree on it.
  let(:ai_email) do
    Rails.root.join('app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/specs/fixtures/aiEmail.mjml').read
  end

  def attribute_children(mjml)
    head = mjml[mjml.index('<mj-head>')..(mjml.index('</mj-head>') + 9)]
    Nokogiri::XML(head, &:strict).at('mj-attributes').element_children.map(&:name)
  end

  it 'writes every MJML element with an explicit close tag' do
    out = described_class.call(ai_email)

    expect(out.split('<br/>').join).not_to include('/>')
    expect(out).to include('<mj-all font-family="Arial, Helvetica, sans-serif"></mj-all>')
    expect(out).to include('<mj-spacer height="24px"></mj-spacer>')
    expect(out).to include('<mj-image src="https://example.com/logo.png" alt="Hub2you Insurtech" width="240px" align="center"></mj-image>')
    expect(attribute_children(out)).to eq(%w[mj-all mj-text mj-section mj-button mj-image mj-divider])
  end

  it 'keeps the inner HTML of ending tags verbatim' do
    out = described_class.call(ai_email)

    expect(out).to include('line-height="1.2" padding="16px 0 0">IA no seguro.<br/>Onde está o<br/>próximo negócio?</mj-text>')
    expect(out).to include('(https://segurogta.com.br/2020/noticia/?cit=502&def=gta-inova-com-lan-amento-de-assistente-virtual)')
    expect(out).to include('<a href="{{ unsubscribe_url }}" style="color:#4B479B;text-decoration:underline;">Cancelar inscrição</a>')
  end

  it 'produces the same canonical MJML as the editor (idempotent)' do
    once = described_class.call(ai_email)

    expect(described_class.call(once)).to eq(once)
  end

  it 'survives HTML entities and bare ampersands outside ending tags' do
    mjml = '<mjml><mj-body><mj-section><mj-column>' \
           '<mj-image src="https://x.test/a.png?w=1&h=2" alt="&copy; Marca &amp; Cia" />' \
           '<mj-text>Tudo&nbsp;certo &mdash; &copy; 2026<br></mj-text>' \
           '</mj-column></mj-section></mj-body></mjml>'

    out = described_class.call(mjml)

    expect(out).to include('src="https://x.test/a.png?w=1&amp;h=2"')
    expect(out).to include('alt="© Marca &amp; Cia"')
    expect(out).to include('<mj-text>Tudo&nbsp;certo &mdash; &copy; 2026<br></mj-text>')
    expect(out).to include('></mj-image>')
  end

  it 'keeps comments verbatim, entities and all' do
    mjml = "<!--\n  Template: Thank You & Review -- notes\n-->\n<mjml><mj-body><!-- Footer & socials --><mj-section></mj-section></mj-body></mjml>"

    expect(described_class.call(mjml)).to eq(mjml)
  end

  it 'lifts nested defaults of a corrupted saved head back to mj-attributes' do
    corrupted = '<mjml><mj-head><mj-attributes>' \
                '<mj-all font-family="Arial"><mj-text color="#111" line-height="1.6">' \
                '<mj-button font-family="Arial"></mj-button></mj-text></mj-all>' \
                '</mj-attributes></mj-head>' \
                '<mj-body><mj-section><mj-column><mj-text>Oi</mj-text></mj-column></mj-section></mj-body></mjml>'

    out = described_class.call(corrupted)

    expect(out).to include('<mj-attributes><mj-all font-family="Arial"></mj-all><mj-text color="#111" line-height="1.6"></mj-text>' \
                           '<mj-button font-family="Arial"></mj-button></mj-attributes>')
    expect(out).to include('<mj-text>Oi</mj-text>')
  end

  it 'canonicalizes fragments with several root sections' do
    fragment = '<mj-section><mj-column><mj-image src="a.png"/></mj-column></mj-section>' \
               '<mj-section><mj-column><mj-spacer/></mj-column></mj-section>'

    expect(described_class.call(fragment)).to eq(
      '<mj-section><mj-column><mj-image src="a.png"></mj-image></mj-column></mj-section>' \
      '<mj-section><mj-column><mj-spacer></mj-spacer></mj-column></mj-section>'
    )
  end

  it 'returns unparseable MJML unchanged and logs a warning' do
    broken = '<mjml><mj-body><mj-section><mj-column></mj-section></mj-body></mjml>'
    allow(Rails.logger).to receive(:warn)

    expect(described_class.call(broken)).to eq(broken)
    expect(Rails.logger).to have_received(:warn).with(include('MjmlCanonicalizer'))
  end

  it 'returns blank input unchanged' do
    expect(described_class.call('')).to eq('')
    expect(described_class.call(nil)).to eq('')
  end
end
