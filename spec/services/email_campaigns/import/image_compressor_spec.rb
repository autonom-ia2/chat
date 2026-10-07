require 'rails_helper'

# Compressão das imagens importadas (#1099, entrega B): até 1200 px e 200 KB, com libvips. Precisa da libvips de
# verdade (a imagem de produção e o CI a instalam); onde ela não existe, o exemplo é marcado como pendente com o motivo.
RSpec.describe EmailCampaigns::Import::ImageCompressor, :aggregate_failures do
  before do
    require 'image_processing/vips'
  rescue LoadError => e
    skip "libvips indisponível nesta máquina: #{e.class}"
  end

  def noise_jpeg(width, height)
    bands = Array.new(3) { Vips::Image.gaussnoise(width, height, mean: 128, sigma: 60) }
    bands.first.bandjoin(bands.drop(1)).cast(:uchar).jpegsave_buffer(Q: 100)
  end

  it 'keeps a small PNG byte for byte' do
    png = Vips::Image.black(10, 10).pngsave_buffer

    output = described_class.call(png, 'image/png')

    expect(output).to have_attributes(bytes: png, content_type: 'image/png', extension: 'png', compressed: false)
  end

  it 'brings a wide and heavy photo down to 1200 px and 200 KB' do
    jpeg = noise_jpeg(2400, 1600)
    expect(jpeg.bytesize).to be > 200.kilobytes

    output = described_class.call(jpeg, 'image/jpeg')
    image = Vips::Image.new_from_buffer(output.bytes, '')

    expect(output.bytes.bytesize).to be <= 200.kilobytes
    expect(image.width).to be <= 1200
    expect(output).to have_attributes(content_type: 'image/jpeg', compressed: true)
  end

  it 'turns WebP into a format every e-mail program shows' do
    webp = Vips::Image.black(20, 20).webpsave_buffer

    output = described_class.call(webp, 'image/webp')

    expect(output.content_type).to eq('image/jpeg').or eq('image/png')
  end

  it 'refuses an image with too many pixels before decoding it' do
    huge = Vips::Image.black(8000, 8000).pngsave_buffer(compression: 9)

    expect { described_class.call(huge, 'image/png') }.to raise_error(described_class::Unfit)
  end
end
