require 'rails_helper'

RSpec.describe EmailCampaigns::LockedFooter, :aggregate_failures do
  let(:shared) do
    JSON.parse(Rails.root.join('app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/' \
                               'lockedFooter.json').read)
  end
  let(:unsubscribe) { '{{ unsubscribe_url }}' }

  def sanitize(mjml)
    EmailCampaigns::Ai::Sanitizer.new(mjml).perform
  end

  def email(*sections)
    "<mjml><mj-body>#{sections.join}</mj-body></mjml>"
  end

  def section(inner, attrs = '')
    "<mj-section#{attrs}><mj-column>#{inner}</mj-column></mj-section>"
  end

  it 'is read from the JSON the editor uses, by the sanitizer fallback and by the AI prompt' do
    expect(described_class::MJML).to eq(shared.fetch('mjml'))
    expect(EmailCampaigns::Ai::Sanitizer::FALLBACK_FOOTER).to eq(described_class::MJML)
    expect(EmailCampaigns::Ai::PromptBuilder.generate(brand: 'Loja')).to include(described_class.with_first_line('MARCA'))
  end

  it 'locks the footer a template already has instead of appending a second unsubscribe link' do
    own_footer = section('<mj-text align="center"><a href="#">View in browser</a> &nbsp;|&nbsp; ' \
                         '<a href="{{ unsubscribe_url }}" style="color:#208e7c;">Unsubscribe</a></mj-text>',
                         ' background-color="#fff6ed" padding="14px 0 0 0"')
    out = sanitize(email(section('<mj-text>Oi</mj-text>'), own_footer))

    expect(out.scan(unsubscribe).size).to eq(1)
    expect(out).to include('<mj-section background-color="#fff6ed" padding="14px 0 0 0" css-class="footer-locked">')
    expect(out).not_to include(described_class::MJML)
    expect(sanitize(out)).to eq(out)
  end

  it 'keeps the classes the section already has' do
    out = sanitize(email(section("<mj-text><a href=\"#{unsubscribe}\">Sair</a></mj-text>", ' css-class="rodape"')))

    expect(out).to include('<mj-section css-class="rodape footer-locked">')
  end

  it 'locks the section of an unsubscribe button' do
    out = sanitize(email(section("<mj-button href=\"#{unsubscribe}\">One-Click Unsubscribe</mj-button>"),
                         section('<mj-text>Fim</mj-text>')))

    expect(out.scan(unsubscribe).size).to eq(1)
    expect(out).to include('<mj-section css-class="footer-locked"><mj-column><mj-button')
  end

  it "points another platform's unsubscribe merge tag at ours and locks its section" do
    body = section('<mj-text><a href="*|UNSUB|*">Descadastrar</a></mj-text>') +
           section('<mj-button href="{{unsubscribe_link}}">Sair</mj-button>')
    out = sanitize(email(body))

    expect(out).not_to include('*|UNSUB|*', '{{unsubscribe_link}}')
    expect(out.scan(unsubscribe).size).to eq(2)
    expect(out.scan('footer-locked').size).to eq(1)
    expect(out).to include(%(<mj-section css-class="footer-locked"><mj-column><mj-button href="#{unsubscribe}">))
  end

  it 'leaves an already locked footer alone' do
    locked = section("<mj-text><a href=\"#{unsubscribe}\">Sair</a></mj-text>", ' css-class="footer-locked"')
    mjml = email(section('<mj-text>Oi</mj-text>'), locked)

    expect(sanitize(mjml)).to eq(EmailCampaigns::MjmlCanonicalizer.call(mjml))
  end

  it 'appends the shared footer once when there is no unsubscribe link' do
    out = sanitize(email(section('<mj-text>Oi <a href="https://loja.test">loja</a></mj-text>')))

    expect(out.scan(unsubscribe).size).to eq(1)
    expect(out).to end_with("#{described_class::MJML}</mj-body></mjml>")
    expect(sanitize(out)).to eq(out)
  end
end
