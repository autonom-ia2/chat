require 'rails_helper'

RSpec.describe BrandKits::SiteImporter do
  let(:fixtures) { Rails.root.join('spec/fixtures/files/brand_kits') }
  let(:requested) { [] }

  # Sem rede: cada URL conhecida devolve o arquivo local; qualquer outra responde 404.
  def stub_site(pages)
    allow(SafeFetch).to receive(:fetch) do |url, **options, &block|
      requested << [url, options]
      body, content_type = pages[url]
      raise SafeFetch::HttpError.new('404 Not Found', status: 404) if body.nil?

      tempfile = Tempfile.new('brand-kit-fixture', binmode: true)
      tempfile.write(body)
      tempfile.rewind
      block.call(SafeFetch::Result.new(tempfile: tempfile, filename: 'fixture', content_type: content_type))
    ensure
      tempfile&.close!
    end
  end

  def fixture(path)
    File.binread(fixtures.join(path))
  end

  context 'with a Next.js + Tailwind site modeled on hub2you.ai' do
    before do
      stub_site(
        'https://hub2you.ai/' => [fixture('hub2you/index.html'), 'text/html'],
        'https://hub2you.ai/_next/static/chunks/dca7c9bcbbd7a07d.css' => [fixture('hub2you/site.css'), 'text/css']
      )
    end

    let(:proposal) { described_class.new('hub2you.ai').perform }
    let(:appearance) { proposal['appearance'] }

    it 'reads the page and its same-site stylesheet within the limits' do
      proposal
      expect(requested.map(&:first)).to eq(['https://hub2you.ai/', 'https://hub2you.ai/_next/static/chunks/dca7c9bcbbd7a07d.css'])
      page_options = requested.first.last
      expect(page_options[:max_bytes]).to eq(described_class::PAGE_MAX_BYTES)
      expect(page_options[:total_timeout]).to be <= described_class::TOTAL_DEADLINE
      expect(requested.last.last[:max_bytes]).to eq(described_class::STYLESHEET_MAX_BYTES)
      expect(proposal['metrics']).to include('requests' => 2)
    end

    it 'finds the brand name and the header logo (not the hero photo)' do
      expect(proposal['name']).to eq('Hub2You')
      expect(appearance['logo_url']).to eq('https://hub2you.ai/logos/hub2you-white-blue-horizontal.png')
      expect(proposal['logo_candidates'].first).to include('url' => 'https://hub2you.ai/logos/hub2you-white-blue-horizontal.png')
      expect(proposal['logo_candidates'].pluck('url')).not_to include('https://hub2you.ai/plataforma/hero-poster.webp')
    end

    it 'assigns the palette roles: CTA red as primary, cyan accent, navy background, readable ink' do
      palette = appearance['palette']

      expect(palette['primary']).to eq('#ff1f2d')
      expect(palette['accent']).to eq('#0ab9d1')
      expect(palette['background']).to eq('#0b243f')
      expect(palette['ink']).to eq('#ffffff')
      expect(BrandKits::Color.contrast(palette['ink'], palette['background'])).to be >= 4.5
      expect(BrandKits::Color.contrast(palette['muted'], palette['surface'])).to be >= 4.5
      expect(proposal['fields']['palette.primary']).to include('source' => 'button_background')
    end

    it 'resolves the fonts through CSS variables and maps them to Google Fonts' do
      typography = appearance['typography']

      expect(typography['heading_font']).to eq('MuseoModerno')
      expect(typography['body_font']).to eq('Roboto')
      expect(typography['google_font_url']).to eq('https://fonts.googleapis.com/css2?family=MuseoModerno&family=Roboto&display=swap')
      expect(typography['fallback']).to eq('Arial, Helvetica, sans-serif')
      expect(proposal['fields']['typography.google_font_url']).to include('source' => 'catalog')
    end

    it 'keeps profile links (without tracking query) and ignores share links' do
      expect(appearance['social_links']).to eq([
                                                 { 'network' => 'linkedin', 'url' => 'https://www.linkedin.com/company/hub2you-insurtech' },
                                                 { 'network' => 'whatsapp', 'url' => 'https://wa.me/5511944547873' }
                                               ])
    end

    it 'fills the footer with what the page has and warns about what it lacks' do
      expect(appearance['footer']).to include('company_name' => 'Hub2You', 'website' => 'https://hub2you.ai', 'address' => nil)
      expect(proposal['warnings']).to include('address_not_found')
    end

    it 'produces an appearance that the strict writer accepts' do
      expect(BrandKits::Appearance.new(appearance)).to be_valid
    end
  end

  context 'with a classic site (JSON-LD, Google Fonts link, theme-color, SVG logo)' do
    before do
      stub_site(
        'https://aurora.example/' => [fixture('classic/index.html'), 'text/html; charset=utf-8'],
        'https://aurora.example/assets/theme.css' => [fixture('classic/theme.css'), 'text/css']
      )
    end

    let(:proposal) { described_class.new('https://aurora.example/').perform }
    let(:appearance) { proposal['appearance'] }

    it 'does not fetch third-party stylesheets nor the Google Fonts CSS, and survives a missing one' do
      proposal
      urls = requested.map(&:first)
      expect(urls).to include('https://aurora.example/assets/theme.css', 'https://aurora.example/assets/missing.css')
      expect(urls).not_to include('https://static.tracker-cdn.test/widget.css')
      expect(urls.none? { |url| url.include?('fonts.googleapis.com') }).to be(true)
      expect(proposal['warnings']).to include('stylesheet_failed')
    end

    it 'uses the Google Fonts link of the page and the declared families' do
      expect(appearance['typography']).to include(
        'heading_font' => 'Lora', 'body_font' => 'Open Sans',
        'google_font_url' => 'https://fonts.googleapis.com/css2?family=Lora:wght@700&family=Open+Sans&display=swap'
      )
      expect(proposal['fields']['typography.google_font_url']).to include('source' => 'link', 'confidence' => 'high')
    end

    it 'takes the brand color from the custom property and button rule, the ink and background from body' do
      palette = appearance['palette']

      expect(palette['primary']).to eq('#7a3e9d')
      expect(palette['accent']).to eq('#e8a33d')
      expect(palette['background']).to eq('#fffaf3')
      expect(palette['ink']).to eq('#2b2b2b')
      expect(palette['surface']).to eq('#ffffff')
    end

    it 'skips the SVG logo, prefers the raster one and warns' do
      expect(appearance['logo_url']).to eq('https://aurora.example/img/logo-aurora.png')
      expect(proposal['warnings']).to include('svg_logo_skipped')
    end

    it 'reads socials from JSON-LD sameAs and anchors, normalizing the WhatsApp send link' do
      expect(appearance['social_links']).to contain_exactly(
        { 'network' => 'instagram', 'url' => 'https://instagram.com/padariaaurora' },
        { 'network' => 'youtube', 'url' => 'https://www.youtube.com/@padariaaurora' },
        { 'network' => 'tiktok', 'url' => 'https://tiktok.com/@padariaaurora' },
        { 'network' => 'x', 'url' => 'https://x.com/padariaaurora' },
        { 'network' => 'whatsapp', 'url' => 'https://wa.me/5511999998888' }
      )
    end

    it 'reads the footer from the JSON-LD organization and its postal address' do
      expect(appearance['footer']).to eq(
        'company_name' => 'Padaria Aurora',
        'address' => 'Rua das Flores, 10, São Paulo, SP, 01000-000, BR',
        'phone' => '+55 11 3333-4444',
        'website' => 'https://aurora.example'
      )
      expect(proposal['fields']['footer.address']).to include('source' => 'json_ld', 'confidence' => 'high')
    end
  end

  context 'when the page has no stylesheet, brand font or logo' do
    # Pilha de fonte do sistema (Tailwind padrão): Roboto aparece na lista, mas não é a fonte da marca.
    let(:plain_page) do
      '<html><head><title>Plain</title><style>body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}</style>' \
        '</head><body><p>Oi</p></body></html>'
    end

    before do
      stub_site('https://plain.example/' => [plain_page, 'text/html'])
    end

    it 'falls back to safe defaults and says so' do
      proposal = described_class.new('https://plain.example').perform

      expect(proposal['appearance']['palette']).to include('background' => '#ffffff', 'surface' => '#ffffff')
      expect(proposal['appearance']['typography']).to include('heading_font' => nil, 'body_font' => nil, 'google_font_url' => nil)
      expect(proposal['warnings']).to include('colors_not_found', 'fonts_not_found', 'logo_not_found')
      expect(BrandKits::Appearance.new(proposal['appearance'])).to be_valid
    end
  end

  describe 'failures' do
    it 'refuses URLs that are not a public web page address' do
      ['ftp://example.com', 'https://user:pass@example.com', 'https://example.com:8443', 'javascript:alert(1)', '', 'https://']
        .each do |url|
          expect { described_class.new(url).perform }
            .to raise_error(described_class::Error) { |error| expect(error.code).to eq('invalid_url') }
        end
    end

    it 'refuses localhost and private addresses (SSRF) through SafeFetch' do
      %w[http://127.0.0.1/ http://localhost/ http://169.254.169.254/latest/meta-data http://10.0.0.5/].each do |url|
        expect { described_class.new(url).perform }
          .to raise_error(described_class::Error) { |error| expect(error.code).to eq('unsafe_url') }
      end
    end

    it 'maps fetch failures to stable codes' do
      {
        SafeFetch::HttpError.new('500', status: 500) => 'http_error',
        SafeFetch::FileTooLargeError.new('big') => 'page_too_large',
        SafeFetch::UnsupportedContentTypeError.new('pdf') => 'not_html',
        SafeFetch::TotalTimeoutError.new('slow') => 'timeout',
        SafeFetch::FetchError.new('reset') => 'fetch_failed'
      }.each do |error, code|
        allow(SafeFetch).to receive(:fetch).and_raise(error)
        expect { described_class.new('https://example.com').perform }
          .to raise_error(described_class::Error) { |raised| expect(raised.code).to eq(code) }
      end
    end
  end
end
