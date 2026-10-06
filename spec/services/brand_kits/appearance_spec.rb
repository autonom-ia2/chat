require 'rails_helper'

RSpec.describe BrandKits::Appearance do
  let(:palette) do
    { primary: '#FF1F2D', accent: '#0ab9d1', ink: '#ffffff', muted: '#c9d1da', surface: '#1e3550', background: '#0b243f', tint: '#3a2a40' }
  end
  let(:raw) do
    {
      palette: palette,
      typography: { heading_font: 'MuseoModerno', body_font: 'Roboto', google_font_url: 'https://fonts.googleapis.com/css2?family=Roboto' },
      logo_url: 'https://hub2you.ai/logos/logo.png',
      social_links: [{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' }],
      footer: { company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo', phone: '+55 11 94454-7873', website: 'https://hub2you.ai' }
    }
  end

  it 'normalizes a valid appearance and always sets the Arial fallback' do
    appearance = described_class.new(raw)

    expect(appearance).to be_valid
    expect(appearance.to_h['palette']['primary']).to eq('#ff1f2d')
    expect(appearance.to_h['typography']['fallback']).to eq('Arial, Helvetica, sans-serif')
    expect(appearance.to_h['social_links']).to eq([{ 'network' => 'linkedin', 'url' => 'https://www.linkedin.com/company/hub2you-insurtech' }])
  end

  it 'drops unknown keys at every level (tolerant reader) and still validates what it keeps' do
    appearance = described_class.new(raw.deep_merge(future: { x: 1 }, palette: { glow: '#000000' },
                                                    typography: { weight: 900 }, footer: { fax: '1' }))

    expect(appearance).to be_valid
    expect(appearance.to_h.keys).to match_array(%w[palette typography logo_url social_links footer])
    expect(appearance.to_h['palette'].keys).to match_array(described_class::PALETTE_ROLES)
    expect(appearance.to_h['footer'].keys).to match_array(%w[company_name address phone website])
  end

  it 'refuses colors that are not #RRGGBB (strict writer)' do
    appearance = described_class.new(raw.deep_merge(palette: { primary: 'red', accent: nil }))

    expect(appearance).not_to be_valid
    expect(appearance.errors).to include('palette.primary', 'palette.accent')
  end

  it 'accepts a Google Fonts URL only from fonts.googleapis.com over https' do
    %w[http://fonts.googleapis.com/css2?family=Roboto https://evil.example/css2?family=Roboto
       https://fonts.googleapis.com.evil.example/css].each do |url|
      appearance = described_class.new(raw.deep_merge(typography: { google_font_url: url }))
      expect(appearance.errors).to include('typography.google_font_url'), url
    end
    expect(described_class.new(raw.deep_merge(typography: { google_font_url: nil }))).to be_valid
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

  it 'reads an empty or missing appearance without raising' do
    expect(described_class.new(nil).errors).to include('palette.primary')
    expect(described_class.new('not a hash').to_h['social_links']).to eq([])
  end
end
