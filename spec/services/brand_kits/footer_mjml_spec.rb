require 'rails_helper'

RSpec.describe BrandKits::FooterMjml do
  let(:payload) do
    { footer: { company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo/SP', website: 'https://hub2you.ai/' },
      social_links: [{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' },
                     { network: 'whatsapp', url: 'https://wa.me/5511999998888' }] }
  end

  def footer(data = payload)
    described_class.new(data).to_s
  end

  it 'is the canonical locked footer with the identity line on top, never a second footer' do
    mjml = footer

    canonical = EmailCampaigns::LockedFooter::MJML
    expect(mjml).to start_with(canonical[0, canonical.index('<mj-text')])
    expect(mjml).to end_with(canonical[canonical.index('Você recebeu')..])
    expect(mjml.scan('footer-locked').size).to eq(1)
    expect(mjml.scan('{{ unsubscribe_url }}').size).to eq(1)
  end

  it 'writes company · address · site, the site as a link with its host' do
    expect(footer).to include('Hub2You · Av. Paulista, 1000 - São Paulo/SP · ' \
                              '<a href="https://hub2you.ai/" style="color:#4b5563;text-decoration:underline;">hub2you.ai</a>')
  end

  it 'adds the social networks as text links (no image from another host)' do
    mjml = footer

    expect(mjml).to include('<a href="https://www.linkedin.com/company/hub2you-insurtech" ' \
                            'style="color:#4b5563;text-decoration:underline;">LinkedIn</a> · ')
    expect(mjml).to include('>WhatsApp</a>')
    expect(mjml).not_to include('mj-social')
    expect(mjml).not_to include('<img')
  end

  it 'escapes every value taken from the kit' do
    data = payload.deep_merge(footer: { company_name: '<script>alert(1)</script> & Cia', address: '"Rua" <b>' })

    mjml = footer(data)

    expect(mjml).to include('&lt;script&gt;alert(1)&lt;/script&gt; &amp; Cia')
    expect(mjml).to include('&quot;Rua&quot; &lt;b&gt;')
    expect(mjml).not_to include('<script>')
  end

  it 'is the plain canonical footer when the kit has no identity line nor networks' do
    expect(footer({ footer: {}, social_links: [] })).to eq(EmailCampaigns::LockedFooter::MJML)
  end

  it 'parses as balanced XML' do
    document = Nokogiri::XML("<root>#{footer.gsub('<br/>', '<br></br>')}</root>", &:strict)

    expect(document.at_xpath('//mj-section/mj-column/mj-text')).to be_present
  end
end
