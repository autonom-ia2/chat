require 'rails_helper'

RSpec.describe EmailCampaigns::MjmlCanonicalizer, :aggregate_failures do
  # Same real AI e-mail (anonymized) used by the editor spec, so front and back agree on it.
  let(:ai_email) do
    Rails.root.join('app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/specs/fixtures/aiEmail.mjml').read
  end
  let(:font) { 'font-family="Arial, Helvetica, sans-serif"' }

  it 'writes every MJML element with an explicit close tag' do
    out = described_class.call(ai_email)

    expect(out.split('<br/>').join).not_to include('/>')
    expect(out).to include('<mj-spacer height="24px"></mj-spacer>')
  end

  it 'resolves the mj-attributes defaults into the body and drops mj-attributes' do
    out = described_class.call(ai_email)

    expect(out).not_to include('mj-attributes', '<mj-all')
    expect(out).to include("<mj-head>\n\n</mj-head>")
    expect(out).to include(%(<mj-text color="#666574" #{font} font-size="16px" line-height="1.6" padding="0">Olá {{ nome }},</mj-text>))
    expect(out).to include('<mj-image src="https://example.com/logo.png" alt="Hub2you Insurtech" width="240px" align="center" ' \
                           'padding="0"></mj-image>')
    expect(out).to include(%(padding="32px 0 0" #{font} background-color="#4B479B" color="#FFFFFF" font-size="16px" font-weight="700" ) \
                           'border-radius="8px" inner-padding="14px 36px">')
    expect(out).to include('<mj-divider border-color="#F1F1FA" border-width="1px" padding="0"></mj-divider>')
    expect(out).to include('<mj-section background-color="#FFFFFF" padding="32px 24px">')
  end

  it 'keeps the inner HTML of ending tags verbatim' do
    out = described_class.call(ai_email)

    expect(out).to include(%(padding="16px 0 0" #{font} color="#252432">IA no seguro.<br/>Onde está o<br/>próximo negócio?</mj-text>))
    expect(out).to include('(https://segurogta.com.br/2020/noticia/?cit=502&def=gta-inova-com-lan-amento-de-assistente-virtual)')
    expect(out).to include('<a href="{{ unsubscribe_url }}" style="color:#4B479B;text-decoration:underline;">Cancelar inscrição</a>')
  end

  it 'is idempotent' do
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

  it 'brings back the defaults of a corrupted head saved by the old editor' do
    corrupted = '<mjml><mj-head><mj-attributes>' \
                '<mj-all font-family="Arial"><mj-text color="#111" line-height="1.6">' \
                '<mj-button background-color="#4B479B"><mj-image padding="0"></mj-image></mj-button></mj-text></mj-all>' \
                '</mj-attributes></mj-head>' \
                '<mj-body><mj-section><mj-column><mj-text>Oi</mj-text><mj-button href="https://x.test">Ir</mj-button>' \
                '</mj-column></mj-section></mj-body></mjml>'

    expect(described_class.call(corrupted)).to eq(
      '<mjml><mj-head></mj-head><mj-body><mj-section><mj-column>' \
      '<mj-text font-family="Arial" color="#111" line-height="1.6">Oi</mj-text>' \
      '<mj-button href="https://x.test" font-family="Arial" background-color="#4B479B">Ir</mj-button>' \
      '</mj-column></mj-section></mj-body></mjml>'
    )
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
