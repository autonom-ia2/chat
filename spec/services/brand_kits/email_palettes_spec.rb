require 'rails_helper'

RSpec.describe BrandKits::EmailPalettes do
  def contrast(first, second)
    BrandKits::Color.contrast(first, second)
  end

  let(:dark_site) do
    { 'primary' => '#ff1f2d', 'accent' => '#0ab9d1', 'ink' => '#ffffff', 'muted' => '#c9d1da',
      'surface' => '#1e3550', 'background' => '#0b243f', 'tint' => '#3a2a40' }
  end
  let(:light_site) do
    { 'primary' => '#5b3df5', 'accent' => '#14a594', 'ink' => '#16213a', 'muted' => '#556070',
      'surface' => '#ffffff', 'background' => '#ffffff', 'tint' => '#f1eefe' }
  end

  describe 'light version (recommended for e-mail)' do
    it 'turns a dark site into a white e-mail with the site navy as text and the dark top band' do
      light = described_class.from_site(dark_site)['light']

      expect(light).to include('background' => '#ffffff', 'surface' => '#ffffff', 'ink' => '#0b243f',
                               'primary' => '#e61c29', 'accent' => '#0ab9d1', 'band' => '#0b243f')
    end

    it 'keeps every text role readable (WCAG AA) and the buttons visible on white' do
      [dark_site, light_site].each do |site|
        light = described_class.from_site(site)['light']

        expect(contrast(light['ink'], light['surface'])).to be >= 4.5
        expect(contrast(light['muted'], light['surface'])).to be >= 4.5
        expect(contrast(light['muted'], light['tint'])).to be >= 4.5
        expect(contrast(light['ink'], light['tint'])).to be >= 4.5
        expect(contrast(light['primary'], light['surface'])).to be >= 3
        expect(contrast('#ffffff', light['primary'])).to be >= 4.5
      end
    end

    it 'uses a light tint of the button color as the top band of a light site' do
      light = described_class.from_site(light_site)['light']

      expect(light['band']).to eq(light['tint'])
      expect(light['ink']).to eq('#16213a')
    end

    it 'swaps a button color too light for white for the accent, then for the text color (details are decorative and keep the site accent)' do
      light = described_class.from_site(dark_site.merge('primary' => '#fff3a0', 'accent' => '#0a6f80'))['light']
      expect(light['primary']).to eq('#0a6f80')

      light = described_class.from_site(dark_site.merge('primary' => '#fff3a0', 'accent' => '#f0f0f0'))['light']
      expect(light['primary']).to eq(light['ink'])
    end
  end

  describe 'dark version (like the site)' do
    it 'keeps a dark site as it is, with the background as the top band' do
      dark = described_class.from_site(dark_site)['dark']

      expect(dark).to include('background' => '#0b243f', 'surface' => '#1e3550', 'ink' => '#ffffff',
                              'primary' => '#ff1f2d', 'band' => '#0b243f')
    end

    it 'builds a dark e-mail from a light site with readable light text' do
      dark = described_class.from_site(light_site)['dark']

      expect(BrandKits::Color.luminance(dark['background'])).to be < 0.05
      expect(contrast(dark['ink'], dark['surface'])).to be >= 4.5
      expect(contrast(dark['muted'], dark['surface'])).to be >= 4.5
      expect(contrast(dark['primary'], dark['background'])).to be >= 3
    end
  end

  it 'fills every role of both versions even from an empty site palette' do
    palettes = described_class.from_site({})

    %w[light dark].each do |mode|
      expect(palettes[mode].keys).to match_array(described_class::ROLES)
      expect(palettes[mode].values).to all(satisfy { |hex| BrandKits::Color.hex?(hex) })
    end
  end

  it 'tells when white text or a white logo is hard to see on the top band' do
    expect(described_class.light_band?('#0b243f')).to be(false)
    expect(described_class.light_band?('#f1eefe')).to be(true)
  end
end
