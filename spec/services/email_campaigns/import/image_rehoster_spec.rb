require 'rails_helper'

# Imagens da importação (#1099, entrega B): copiadas só por https (sem cair para http), tipo conferido pelos bytes,
# SVG recusado, data: com teto, orçamento de tempo e de quantidade, endereço público permanente; a que falhar vira
# espaço reservado com aviso que bloqueia salvar.
RSpec.describe EmailCampaigns::Import::ImageRehoster, :aggregate_failures do
  let(:account) { create(:account) }
  let(:import) { EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste') }
  let(:report) { EmailCampaigns::Import::Report.new(source_kind: 'paste') }
  let(:png) { Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') }
  let(:svg) { '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>' }
  let(:fetched) { [] }
  let(:bodies) { {} }

  around do |example|
    with_modified_env FRONTEND_URL: 'https://app.exemplo.com.br' do
      example.run
    end
  end

  before do
    allow(EmailCampaigns::Import::ImageCompressor).to receive(:call) do |bytes, content_type|
      EmailCampaigns::Import::ImageCompressor::Output.new(bytes: bytes, content_type: content_type, extension: 'png', compressed: false)
    end
    allow(SafeFetch).to receive(:fetch) do |url, **options, &block|
      fetched << [url, options]
      body = bodies.fetch(url) { raise SafeFetch::HttpError.new('404 Not Found', status: 404) }
      file = Tempfile.new('rehoster-spec', binmode: true)
      file.write(body)
      file.rewind
      block.call(SafeFetch::Result.new(tempfile: file, filename: 'x', content_type: 'image/png'))
    ensure
      file&.close!
    end
  end

  def mjml_with(images, background: nil)
    blocks = images.map { |src| %(<mj-image src="#{src}" alt="Foto"></mj-image>) }.join
    section = background ? %(<mj-section background-url="#{background}">) : '<mj-section>'
    "<mjml><mj-body>#{section}<mj-column>#{blocks}</mj-column></mj-section></mj-body></mjml>"
  end

  def run(mjml, files: {}, deadline: EmailCampaigns::Import::Deadline.new(30))
    report.images = EmailCampaigns::Import::ImageRehoster.sources(mjml).map { |src| { src: src } }
    described_class.call(mjml, report, import: import, files: files, deadline: deadline)
  end

  def image_srcs(mjml)
    Nokogiri::HTML5.fragment(mjml).css('mj-image').map { |node| node['src'] }
  end

  it 'copies remote images over https only and points the design at permanent public addresses' do
    bodies['https://cdn.example.com/a.png'] = png
    bodies['https://cdn.example.com/b.png'] = png
    bodies['https://cdn.example.com/fundo.png'] = png

    out = run(mjml_with(%w[https://cdn.example.com/a.png http://cdn.example.com/b.png], background: 'https://cdn.example.com/fundo.png'))

    expect(fetched.map(&:first)).to contain_exactly('https://cdn.example.com/a.png', 'https://cdn.example.com/b.png',
                                                    'https://cdn.example.com/fundo.png')
    expect(fetched.map(&:last)).to all(include(schemes: ['https'], max_bytes: 5.megabytes, allowed_content_type_prefixes: ['image/']))
    expect(fetched.map { |(_url, options)| options[:total_timeout] }).to all(be_between(0.001, 10))
    expect(out).not_to include('cdn.example.com')
    expect(image_srcs(out)).to all(start_with('https://app.exemplo.com.br/rails/active_storage/blobs/redirect/'))
    expect(Nokogiri::HTML5.fragment(out).at_css('mj-section')['background-url']).to start_with('https://app.exemplo.com.br/')
    expect(import.images.count).to eq(3)
    expect(report.count(:images_copied)).to eq(3)
    expect(report.count(:images_to_copy)).to eq(0)
    expect(report.images).to all(include(status: 'copied'))
  end

  it 'never falls back to http when the https copy fails' do
    out = run(mjml_with(%w[http://cdn.example.com/b.png]))

    expect(fetched.map(&:first)).to eq(['https://cdn.example.com/b.png'])
    expect(image_srcs(out)).to eq([EmailCampaigns::Import::Placeholders::MISSING_SRC])
    expect(Nokogiri::HTML5.fragment(out).at_css('mj-image')['css-class']).to include(EmailCampaigns::Import::Placeholders::MISSING_CLASS)
    expect(report.count(:image_missing)).to eq(1)
    expect(report.to_h[:warnings]).to include(hash_including(code: :image_missing, severity: :blocking))
  end

  it 'refuses SVG (checked by the bytes, not by the name) and anything that is not a raster image' do
    bodies['https://cdn.example.com/logo.png'] = svg
    bodies['https://cdn.example.com/pagina.png'] = '<html><body>oi</body></html>'

    out = run(mjml_with(%w[https://cdn.example.com/logo.png https://cdn.example.com/pagina.png]))

    expect(image_srcs(out)).to all(eq(EmailCampaigns::Import::Placeholders::MISSING_SRC))
    expect(import.images.count).to eq(0)
    expect(report.images).to all(include(status: 'failed', reason: 'unsupported_type'))
  end

  it 'decodes a data: image within its ceiling and refuses one above it without decoding it' do
    small = "data:image/png;base64,#{Base64.strict_encode64(png)}"
    huge = "data:image/png;base64,#{'A' * ((5.megabytes * 4 / 3) + 8)}"
    svg_data = "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"

    out = run(mjml_with([small, huge, svg_data]))

    srcs = image_srcs(out)
    expect(srcs.first).to start_with('https://app.exemplo.com.br/')
    expect(srcs.drop(1)).to all(eq(EmailCampaigns::Import::Placeholders::MISSING_SRC))
    expect(fetched).to be_empty
    expect(report.images.map { |image| image[:reason] }).to eq([nil, 'too_large', 'unsupported_type'])
    expect(report.images.map { |image| image[:src] }).to all(satisfy { |src| src.bytesize < 100 })
  end

  it 'uses the images of a .zip by their relative name, without the network' do
    src = "#{EmailCampaigns::Import::ZipReader::BASE_URL}img/logo.png"

    out = run(mjml_with([src]), files: { 'img/logo.png' => png })

    expect(fetched).to be_empty
    expect(image_srcs(out).first).to start_with('https://app.exemplo.com.br/')
    expect(report.images.first[:src]).to eq('img/logo.png')
  end

  it 'stops at 40 images and when the time budget runs out' do
    sources = (1..41).map { |index| "https://cdn.example.com/#{index}.png" }
    sources.each { |src| bodies[src] = png }

    out = run(mjml_with(sources))

    expect(fetched.size).to eq(40)
    expect(image_srcs(out).last).to eq(EmailCampaigns::Import::Placeholders::MISSING_SRC)
    expect(report.images.last).to include(status: 'failed', reason: 'too_many')

    spent = EmailCampaigns::Import::Deadline.new(30, clock: -> { 0 })
    allow(spent).to receive(:remaining).and_return(0)
    fetched.clear
    later = run(mjml_with(%w[https://cdn.example.com/1.png]), deadline: spent)
    expect(fetched).to be_empty
    expect(image_srcs(later)).to eq([EmailCampaigns::Import::Placeholders::MISSING_SRC])
    expect(report.images.last).to include(reason: 'out_of_time')
  end

  it 'refuses to run without the public address of the installation' do
    bodies['https://cdn.example.com/a.png'] = png

    with_modified_env FRONTEND_URL: '' do
      expect { run(mjml_with(%w[https://cdn.example.com/a.png])) }
        .to raise_error(EmailCampaigns::Import::Error) { |error| expect(error.code).to eq(:configuration) }
    end
  end
end
