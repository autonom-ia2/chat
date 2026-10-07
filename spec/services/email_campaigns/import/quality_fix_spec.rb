require 'rails_helper'

RSpec.describe EmailCampaigns::Import::QualityFix, :aggregate_failures do
  let(:report) { EmailCampaigns::Import::Report.new(source_kind: 'paste') }
  let(:placeholders) { EmailCampaigns::Import::Engine::PLACEHOLDERS }

  def email(content, section_attrs = 'background-color="#ffffff"')
    EmailCampaigns::LockedFooter.ensure(<<~MJML)
      <mjml><mj-head></mj-head><mj-body width="600px" background-color="#ffffff">
        <mj-section #{section_attrs}><mj-column>#{content}</mj-column></mj-section>
      </mj-body></mjml>
    MJML
  end

  def fix(mjml)
    described_class.call(mjml, report, placeholders: placeholders)
  end

  def checks(mjml)
    EmailCampaigns::QualityGate.new(mjml: mjml, remote_images: true, placeholders: placeholders).violations.map(&:check)
  end

  def warning(code)
    report.to_h[:warnings].find { |entry| entry[:code] == code }
  end

  it 'darkens low-contrast text, raises small fonts and sets Arial, inside the text too' do
    mjml = email('<mj-text font-family="Georgia" font-size="11px" color="#c8c8c8">Letras <span style="color:#dddddd;font-size:10px">miúdas</span> ' \
                 'e <a href="https://a.example.com" style="color:#eeeeee">link</a></mj-text>')

    expect(checks(mjml)).to include(:contrast, :font_size, :font_family)
    out = fix(mjml)
    expect(checks(out)).to be_empty
    expect(out).to include('font-family="Arial, Helvetica, sans-serif"', 'font-size="14px"', 'font-size:14px')
    expect(warning(:quality_fixed)[:items]).to include('contrast', 'font_size', 'font_family')
  end

  it 'lightens text on a dark background instead of darkening it' do
    mjml = email('<mj-text font-family="Arial" font-size="16px" color="#333333">Escuro</mj-text>', 'background-color="#111827"')
    node = Nokogiri::HTML5.fragment(fix(mjml)).at('mj-text')

    expect(EmailCampaigns::QualityGate::Contrast.ratio(node['color'], '#111827')).to be >= 4.5
    expect(EmailCampaigns::QualityGate::Contrast.luminance(node['color'])).to be > EmailCampaigns::QualityGate::Contrast.luminance('#333333')
  end

  it 'makes buttons readable and 44px tall' do
    mjml = email('<mj-button font-family="Arial" font-size="13px" inner-padding="4px 10px" background-color="#ffd8c2" color="#ffffff" ' \
                 'href="https://a.example.com">Ver ofertas</mj-button>')
    button = Nokogiri::HTML5.fragment(fix(mjml)).at('mj-button')

    expect(checks(fix(mjml))).to be_empty
    expect(button['font-size']).to eq('14px')
    expect(EmailCampaigns::QualityGate::Contrast.ratio(button['color'], button['background-color'])).to be >= 4.5
    expect(button['inner-padding'].split.first.to_f).to be > 4
  end

  it 'describes images from the text next to them or, failing that, from the file name' do
    mjml = email('<mj-image src="https://a.example.com/img/kit-boas-vindas.jpg"></mj-image>' \
                 '<mj-text font-family="Arial" font-size="16px" color="#111111">Kit de boas-vindas para começar bem</mj-text>' \
                 '<mj-image src="https://a.example.com/img/foto_da_loja.png" alt=""></mj-image>')
    images = Nokogiri::HTML5.fragment(fix(mjml)).css('mj-image')

    expect(images.map { |image| image['alt'] }).to eq(['Kit de boas-vindas para começar bem', 'Kit de boas-vindas para começar bem'])
    lone = Nokogiri::HTML5.fragment(fix(email('<mj-image src="https://a.example.com/img/foto_da_loja.png"></mj-image>'))).at('mj-image')
    expect(lone['alt']).to eq('foto da loja')
  end

  it 'stops after two passes and lists what is still pending' do
    out = fix(email('<mj-text font-family="Arial" font-size="16px" color="#111111">CPF {{ cpf }}</mj-text>'))

    expect(checks(out)).to eq([:placeholders])
    expect(warning(:quality_pending)).to be_nil
  end

  it 'leaves the color of text over a background image alone and lists the contrast as pending' do
    hero = 'background-url="https://img.example.com/hero.jpg"'
    [hero, %(#{hero} background-color="#ffffff")].each do |attrs|
      out = fix(email('<mj-text font-family="Arial" font-size="32px" font-weight="700" color="#ffffff">Black Friday</mj-text>', attrs))

      expect(Nokogiri::HTML5.fragment(out).at('mj-text')['color']).to eq('#ffffff')
    end
    expect(warning(:quality_pending)[:items]).to include('contrast')
  end
end
