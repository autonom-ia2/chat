require 'rails_helper'

RSpec.describe BrandKits::LogoDownloader do
  let(:kit) { create(:brand_kit) }
  let(:png) { Rails.root.join('spec/assets/avatar.png').binread }

  def serve(body, content_type: 'image/png')
    allow(SafeFetch).to receive(:fetch) do |_url, **_options, &block|
      tempfile = Tempfile.new('logo', binmode: true)
      tempfile.write(body)
      tempfile.rewind
      block.call(SafeFetch::Result.new(tempfile: tempfile, filename: 'logo', content_type: content_type))
    ensure
      tempfile&.close!
    end
  end

  it 'attaches a PNG whose bytes really are a PNG, typed by its signature' do
    serve(png, content_type: 'application/octet-stream')

    described_class.new(kit, 'https://hub2you.ai/logos/logo.png').perform

    expect(kit.logo).to be_attached
    expect(kit.logo.content_type).to eq('image/png')
    expect(SafeFetch).to have_received(:fetch)
      .with('https://hub2you.ai/logos/logo.png', hash_including(max_bytes: described_class::MAX_BYTES, total_timeout: described_class::TIMEOUT))
  end

  it 'refuses an SVG or anything that is not PNG/JPEG/WebP/GIF' do
    serve('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', content_type: 'image/png')

    expect { described_class.new(kit, 'https://hub2you.ai/logo.png').perform }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('logo_unsupported_type') }
    expect(kit.reload.logo).not_to be_attached
  end

  it 'turns SSRF refusals into a stable code without fetching' do
    expect { described_class.new(kit, 'http://127.0.0.1/logo.png').perform }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('logo_unsafe_url') }
  end

  it 'accepts an uploaded file with the same signature check' do
    upload = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    described_class.attach_upload(kit, upload)

    expect(kit.logo.content_type).to eq('image/png')
  end

  it 'stores the logo of a site read for one e-mail as a blob, with the same checks' do
    serve(png, content_type: 'application/octet-stream')

    blob = described_class.blob_from('https://aurora.example/logo.png')

    expect(blob).to have_attributes(content_type: 'image/png', filename: ActiveStorage::Filename.new('logo.png'))

    serve('<svg></svg>')
    expect { described_class.blob_from('https://aurora.example/logo.svg') }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('logo_unsupported_type') }
  end
end
