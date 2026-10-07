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

  it 'saves a small image again without its metadata (camera, place), upright, at the same size' do
    jpeg = Vips::Image.black(10, 20).mutate do |image|
      image.set_type!(GObject::GINT_TYPE, 'orientation', 6)
      image.set_type!(GObject::GSTR_TYPE, 'exif-ifd0-Make', 'Camera X')
    end.jpegsave_buffer

    output = described_class.call(jpeg, 'image/jpeg')
    saved = Vips::Image.new_from_buffer(output.bytes, '')

    expect(output).to have_attributes(content_type: 'image/jpeg', extension: 'jpg', compressed: false, animation_lost: false)
    expect(saved.get_fields).not_to include('exif-data', 'orientation')
    expect([saved.width, saved.height]).to eq([20, 10])
  end

  it 'keeps a small animated GIF byte for byte, and warns when one has to stand still to fit' do
    frames = Vips::Image.black(10, 20).cast(:uchar)
    small = frames.mutate { |image| image.set_type!(GObject::GINT_TYPE, 'page-height', 10) }.gifsave_buffer
    expect(described_class.call(small, 'image/gif')).to have_attributes(bytes: small, animation_lost: false)

    wide = Vips::Image.black(1600, 200).mutate { |image| image.set_type!(GObject::GINT_TYPE, 'page-height', 100) }.gifsave_buffer
    expect(described_class.call(wide, 'image/gif')).to have_attributes(animation_lost: true)
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
