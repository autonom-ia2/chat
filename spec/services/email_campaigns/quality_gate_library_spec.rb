require 'rails_helper'

# CI quality gate for the shared library (#1082): every catalog design passes EmailCampaigns::QualityGate and the
# versioned HTML is exactly what `rails email_campaign_templates:compile` produces today. Needs Node and the
# frontend dependencies (mjml-browser), like the CI backend job has.
RSpec.describe EmailCampaigns::QualityGate, :aggregate_failures do
  let(:catalog) { EmailCampaigns::TemplateCatalog }
  let(:locales) do
    %w[en pt_BR].index_with do |locale|
      JSON.parse(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/campaign.json").read)
          .dig('CAMPAIGN', 'EMAIL_CAMPAIGN')
    end
  end

  EmailCampaigns::TemplateCatalog.entries.each do |entry|
    it "#{entry.fetch('key')} passes the quality gate and its versioned HTML is current" do
      compiled = catalog.compile(entry)
      violations = described_class.new(mjml: catalog.body(entry), html: compiled.html, compile_errors: compiled.errors).violations

      expect(violations.map { |violation| "#{violation.check}: #{violation.detail}" }).to eq([])
      expect(catalog.html_path(entry).read).to eq(compiled.html), 'run `rails email_campaign_templates:compile`'
    end
  end

  it 'shares one identical locked footer across the thirteen designs' do
    footers = catalog.entries.flat_map { |entry| described_class.locked_footers(catalog.body(entry)) }

    expect(footers.size).to eq(13)
    expect(footers.uniq.size).to eq(1)
  end

  it 'names every design and category in English and Brazilian Portuguese' do
    locales.each do |locale, strings|
      catalog.entries.each do |entry|
        expect(strings.dig('WORKSPACE', 'MODELS', entry.fetch('key'))).to be_present, "#{locale} MODELS.#{entry.fetch('key')}"
        expect(strings.dig('GALLERY', 'CATEGORIES', entry.fetch('category'))).to be_present, "#{locale} CATEGORIES.#{entry.fetch('category')}"
      end
      expect(strings.dig('WORKSPACE', 'MODELS').keys).to match_array(catalog.entries.map { |entry| entry.fetch('key') })
      expect(strings.dig('GALLERY', 'CATEGORIES').keys).to match_array(catalog.entries.map { |entry| entry.fetch('category') }.uniq)
    end
  end
end
