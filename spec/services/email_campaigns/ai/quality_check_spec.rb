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

  it 'blocks a second footer and an unknown placeholder' do
    content = %(<mj-text #{font} font-size="16px" color="#0b243f">Oi {{ cupom }}</mj-text>)

    result = described_class.new(email(content, footer + footer)).call

    expect(result.blocking.map(&:check)).to contain_exactly(:unsubscribe, :placeholders)
  end

  describe 'size against the Gmail clip (estimated from the MJML)' do
    let(:limit) { EmailCampaigns::QualityGate::MAX_HTML_BYTES }
    let(:estimate) { EmailCampaigns::QualityGate::EstimatedSize }

    def email_with(letters)
      email(%(<mj-text #{font} font-size="16px" color="#0b243f">#{'x' * letters}</mj-text>))
    end

    # An e-mail whose estimated HTML is within a few bytes of `bytes` (each letter of text adds CONTENT_FACTOR).
    def email_estimated_at(bytes)
      empty = estimate.bytes(email_with(0))
      email_with(((bytes - empty) / estimate::CONTENT_FACTOR).floor)
    end

    def size_checks(fraction_of_limit)
      mjml = email_estimated_at((limit * fraction_of_limit).floor)
      expect(estimate.bytes(mjml)).to be_within(5).of(limit * fraction_of_limit)
      result = described_class.new(mjml).call
      [result.blocking.map(&:check), result.warnings.map(&:check)]
    end

    it 'says nothing well below the limit' do
      expect(size_checks(0.84)).to eq([[], []])
    end

    it 'warns (never blocks) when the estimate is within 15% of the limit, on either side' do
      expect(size_checks(0.86)).to eq([[], [:html_size_near]])
      expect(size_checks(1.0)).to eq([[], [:html_size_near]])
      expect(size_checks(1.14)).to eq([[], [:html_size_near]])
    end

    it 'blocks only when the estimate is clearly over the limit' do
      expect(size_checks(1.16)).to eq([[:html_size], []])
    end

    it 'reports the same estimate the QualityGate uses for the import (one source of truth)' do
      mjml = email_estimated_at(limit)
      detail = described_class.new(mjml).call.warnings.find { |violation| violation.check == :html_size_near }.detail

      expect(detail).to include("about #{estimate.bytes(mjml)} bytes")
      expect(EmailCampaigns::QualityGate.new(mjml: mjml).html_bytes).to eq(estimate.bytes(mjml))
    end
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
