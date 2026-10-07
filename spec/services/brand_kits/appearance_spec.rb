require 'rails_helper'

RSpec.describe BrandKits::Appearance do
  let(:palette) do
    { primary: '#FF1F2D', accent: '#0ab9d1', ink: '#ffffff', muted: '#c9d1da', surface: '#1e3550', background: '#0b243f', tint: '#3a2a40' }
  end
  let(:palettes) { BrandKits::EmailPalettes.from_site(palette.transform_keys(&:to_s).transform_values(&:downcase)) }
  let(:raw) do
    {
      palettes: palettes,
      site_palette: palette,
      typography: { heading_font: 'MuseoModerno', body_font: 'Roboto', google_font_url: 'https://fonts.googleapis.com/css2?family=Roboto' },
      logo_url: 'https://hub2you.ai/logos/logo.png',
      social_links: [{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' }],
      footer: { company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo', phone: '+55 11 94454-7873', website: 'https://hub2you.ai' }
    }
  end

  it 'normalizes a valid appearance and always sets the Arial fallback' do
    appearance = described_class.new(raw)

    expect(appearance).to be_valid
    expect(appearance.to_h.dig('palettes', 'light', 'primary')).to eq('#e61c29')
    expect(appearance.to_h.dig('site_palette', 'primary')).to eq('#ff1f2d')
    expect(appearance.to_h['typography']['fallback']).to eq('Arial, Helvetica, sans-serif')
    expect(appearance.to_h['social_links']).to eq([{ 'network' => 'linkedin', 'url' => 'https://www.linkedin.com/company/hub2you-insurtech' }])
  end

  it 'drops unknown keys at every level (tolerant reader) and still validates what it keeps' do
    appearance = described_class.new(raw.deep_merge(future: { x: 1 }, palettes: { 'light' => { glow: '#000000' } },
                                                    typography: { weight: 900 }, footer: { fax: '1' }))

    expect(appearance).to be_valid
    expect(appearance.to_h.keys).to match_array(%w[palettes site_palette typography logo_url social_links footer])
    expect(appearance.to_h.dig('palettes', 'light').keys).to match_array(BrandKits::EmailPalettes::ROLES)
    expect(appearance.to_h['footer'].keys).to match_array(%w[company_name address phone website])
  end

  it 'refuses colors that are not #RRGGBB (strict writer)' do
    appearance = described_class.new(raw.deep_merge(palettes: { 'light' => { 'primary' => 'red', 'band' => nil } }, site_palette: { ink: 'blue' }))

    expect(appearance).not_to be_valid
    expect(appearance.errors).to include('palettes.light.primary', 'palettes.light.band', 'site_palette.ink')
  end

  it 'accepts a Google Fonts URL only from fonts.googleapis.com over https' do
    %w[http://fonts.googleapis.com/css2?family=Roboto https://evil.example/css2?family=Roboto
       https://fonts.googleapis.com.evil.example/css].each do |url|
      appearance = described_class.new(raw.deep_merge(typography: { google_font_url: url }))
      expect(appearance.errors).to include('typography.google_font_url'), url
    end
    expect(described_class.new(raw.deep_merge(typography: { google_font_url: nil }))).to be_valid
  end

  it 'fills the Google Fonts link from the catalog when the fonts changed and no link came' do
    appearance = described_class.new(raw.deep_merge(typography: { heading_font: 'Inter', body_font: 'Lora', google_font_url: nil }))

    expect(appearance.to_h.dig('typography', 'google_font_url')).to eq('https://fonts.googleapis.com/css2?family=Inter&family=Lora&display=swap')
  end

  it 'refuses font names that could break out of a CSS or MJML attribute' do
    appearance = described_class.new(raw.deep_merge(typography: { heading_font: 'Roboto"; color:red' }))

    expect(appearance.errors).to include('typography.heading_font')
  end

  it 'refuses social links for unknown networks or pointing to another host' do
    appearance = described_class.new(raw.merge(social_links: [{ network: 'myspace', url: 'https://myspace.com/x' },
                                                              { network: 'facebook', url: 'https://evil.example/hub2you' },
                                                              { network: 'instagram', url: 'javascript:alert(1)' }]))

    expect(appearance.errors).to include('social_links.0.network', 'social_links.1.url', 'social_links.2.url')
  end

  it 'refuses the same network twice' do
    link = { network: 'linkedin', url: 'https://linkedin.com/company/a' }
    expect(described_class.new(raw.merge(social_links: [link, link])).errors).to include('social_links.1.network')
  end

  it 'refuses a non-http logo or website' do
    appearance = described_class.new(raw.merge(logo_url: 'data:image/png;base64,AAAA').deep_merge(footer: { website: 'ftp://x' }))

    expect(appearance.errors).to include('logo_url', 'footer.website')
  end

  it 'reads an empty or missing appearance without raising, with readable default colors' do
    expect(described_class.new(nil)).to be_valid
    expect(described_class.new('not a hash').to_h['social_links']).to eq([])
  end

  describe 'kits saved with the old single palette' do
    it 'reads the old palette as the site colors and derives both e-mail versions from it' do
      appearance = described_class.new(raw.except(:palettes, :site_palette).merge(palette: palette))

      expect(appearance).to be_valid
      expect(appearance.to_h['site_palette']).to include('background' => '#0b243f')
      expect(appearance.to_h['palettes']).to eq(palettes)
    end

    it 'derives a missing version from the site colors' do
      appearance = described_class.new(raw.merge(palettes: { light: palettes['light'] }))

      expect(appearance.to_h.dig('palettes', 'dark')).to eq(palettes['dark'])
    end
  end
end
