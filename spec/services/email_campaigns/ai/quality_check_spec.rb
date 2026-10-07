require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::QualityCheck, :aggregate_failures do
  let(:font) { %(font-family="'Roboto', Arial, Helvetica, sans-serif") }
  let(:good) do
    <<~MJML
      <mj-text #{font} font-size="16px" color="#0b243f">Olá, {{ nome }}</mj-text>
      <mj-button #{font} background-color="#c8102e" color="#ffffff" font-size="16px" inner-padding="14px 36px" href="https://hub2you.ai">Falar com a equipe</mj-button>
    MJML
  end
  let(:footer) { BrandKits::FooterMjml.new(footer: { company_name: 'Hub2You' }, social_links: []).to_s }

  def email(content, footer_markup = footer)
    <<~MJML
      <mjml>
        <mj-head><mj-font name="Roboto" href="https://fonts.googleapis.com/css2?family=Roboto"></mj-font></mj-head>
        <mj-body background-color="#ffffff">
          <mj-section background-color="#0b243f"><mj-column><mj-image src="https://app.example.com/rails/active_storage/blobs/x/logo.png" alt="Hub2You" width="160px"></mj-image></mj-column></mj-section>
          <mj-section background-color="#ffffff"><mj-column>#{content}</mj-column></mj-section>
          #{footer_markup}
        </mj-body>
      </mjml>
    MJML
  end

  it 'passes an AI e-mail in the brand font with a remote logo (font and image host are not its business)' do
    result = described_class.new(email(good)).call

    expect(result.violations).to be_empty
    expect(result.repair?).to be(false)
  end

  it 'asks for a repair on contrast, small buttons and images without alt, and keeps them as warnings' do
    content = <<~MJML
      <mj-text #{font} font-size="16px" color="#9ca3af">Texto claro demais</mj-text>
      <mj-button #{font} background-color="#c8102e" color="#ffffff" font-size="16px" inner-padding="6px 20px" href="https://hub2you.ai">Pequeno</mj-button>
      <mj-image src="https://app.example.com/x.png"></mj-image>
    MJML

    result = described_class.new(email(content)).call

    expect(result.violations.map(&:check)).to contain_exactly(:contrast, :button_height, :image_alt)
    expect(result.repair?).to be(true)
    expect(result.blocking).to be_empty
    expect(result.warnings.map(&:check)).to contain_exactly(:contrast, :button_height, :image_alt)
  end

  it 'blocks a second footer, an unknown placeholder and an e-mail Gmail would clip' do
    content = %(<mj-text #{font} font-size="16px" color="#0b243f">Oi {{ cupom }}#{'a' * 20_000}</mj-text>)

    result = described_class.new(email(content, footer + footer)).call

    expect(result.blocking.map(&:check)).to contain_exactly(:unsubscribe, :placeholders, :html_size)
  end

  it 'accepts the placeholders of the audience' do
    content = %(<mj-text #{font} font-size="16px" color="#0b243f">Oi {{ cupom }}</mj-text>)

    expect(described_class.new(email(content), placeholders: ['cupom']).call.violations).to be_empty
  end

  it 'writes the report the model gets to fix the e-mail' do
    content = %(<mj-text #{font} font-size="16px" color="#9ca3af">Claro</mj-text>)

    report = described_class.new(email(content)).call.report

    expect(report).to include('contrast', '#9ca3af on #ffffff')
  end
end
