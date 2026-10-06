require 'rails_helper'

RSpec.describe BrandKits::FooterMjml do
  let(:kit) { create(:brand_kit) }

  it 'builds the locked footer with social row, address and the unsubscribe placeholder' do
    mjml = described_class.new(kit).to_s

    expect(mjml).to start_with('<mj-section css-class="footer-locked"')
    expect(mjml).to include('<mj-social-element name="linkedin" href="https://www.linkedin.com/company/hub2you-insurtech"></mj-social-element>')
    expect(mjml).to include('Av. Paulista, 1000 - São Paulo/SP')
    expect(mjml).to include('href="{{ unsubscribe_url }}"')
    expect(mjml).to include('font-family="\'Roboto\', Arial, Helvetica, sans-serif"')
  end

  it 'escapes every value taken from the kit' do
    kit.update!(appearance: kit.appearance.deep_merge('footer' => { 'company_name' => '<script>alert(1)</script> & Cia', 'address' => '"Rua" <b>' }))

    mjml = described_class.new(kit).to_s

    expect(mjml).to include('&lt;script&gt;alert(1)&lt;/script&gt; &amp; Cia')
    expect(mjml).to include('&quot;Rua&quot; &lt;b&gt;')
    expect(mjml).not_to include('<script>')
  end

  it 'never self-closes a tag' do
    expect(described_class.new(kit).to_s).not_to include('/>')
  end

  it 'parses as balanced XML' do
    document = Nokogiri::XML("<root>#{described_class.new(kit)}</root>", &:strict)

    expect(document.at_xpath('//mj-section/mj-column/mj-social')).to be_present
  end

  it 'renders networks MJML has no icon for with the generic web icon and a label' do
    kit.update!(appearance: kit.appearance.merge('social_links' => [{ 'network' => 'whatsapp', 'url' => 'https://wa.me/5511999998888' }]))

    expect(described_class.new(kit).to_s).to include('<mj-social-element name="web" href="https://wa.me/5511999998888">WhatsApp</mj-social-element>')
  end

  it 'leaves the social row out when the kit has no network' do
    kit.update!(appearance: kit.appearance.merge('social_links' => []))

    expect(described_class.new(kit).to_s).not_to include('mj-social')
  end
end
