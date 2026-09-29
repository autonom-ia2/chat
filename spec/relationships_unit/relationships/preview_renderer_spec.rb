require 'tmpdir'
require 'active_support/all'
module Relationships; end
require_relative '../../../enterprise/app/services/relationships/preview_renderer'

RSpec.describe Relationships::PreviewRenderer do
  let(:renderer) { described_class.new }

  { 'png' => 'image/png', 'pdf' => 'application/pdf', 'mp4' => 'video/mp4' }.each do |extension, type|
    it "generates a real bounded JPEG from a synthetic #{extension} fixture" do
      Dir.mktmpdir do |directory|
        output = File.join(directory, 'preview.jpg')
        expect(renderer.render(type, File.expand_path("../../assets/sample.#{extension}", __dir__), output)).to be(true)
        expect(File.binread(output, 2)).to eq("\xFF\xD8".b)
        expect(File.size(output)).to be <= described_class::MAX_OUTPUT
      end
    end
  end

  %w[jpg webp].each do |extension|
    it "converts a real #{extension} image using only its explicit loader" do
      require 'vips'
      Dir.mktmpdir do |directory|
        input = File.join(directory, "input.#{extension}")
        Vips::Image.pngload(File.expand_path('../../assets/sample.png', __dir__)).write_to_file(input)
        content_type = extension == 'jpg' ? 'image/jpeg' : 'image/webp'
        output = File.join(directory, 'preview.jpg')
        expect(renderer.render(content_type, input, output)).to be(true)
        expect(File.binread(output, 2)).to eq("\xFF\xD8".b)
      end
    end
  end

  it 'rejects SVG, playlists, PDF and GIF declared as any allowed image type before spawning' do
    require 'vips'
    Dir.mktmpdir do |directory|
      external = File.expand_path('../../assets/sample.png', __dir__)
      inputs = {
        'svg' => %(<svg xmlns="http://www.w3.org/2000/svg"><image href="file://#{external}"/><image href="http://127.0.0.1:9/image"/></svg>),
        'playlist' => "ffconcat version 1.0\nfile '#{external}'\n",
        'pdf' => File.binread(File.expand_path('../../assets/sample.pdf', __dir__))
      }
      gif = File.join(directory, 'input.gif')
      Vips::Image.pngload(external).write_to_file(gif)
      inputs['gif'] = File.binread(gif)
      expect(Process).not_to receive(:spawn)
      inputs.each do |extension, bytes|
        original = File.join(directory, "input.#{extension}")
        File.binwrite(original, bytes)
        described_class::IMAGE_TYPES.each do |content_type|
          output = File.join(directory, 'preview.jpg')
          expect(renderer.render(content_type, original, output)).to be(false)
          expect(File).not_to exist(output)
        end
      end
    end
  end

  it 'rejects mismatched image signatures and a truncated image bearing a valid PNG signature' do
    Dir.mktmpdir do |directory|
      input = File.expand_path('../../assets/sample.png', __dir__)
      output = File.join(directory, 'preview.jpg')
      expect(renderer.render('image/jpeg', input, output)).to be(false)
      expect(renderer.render('image/webp', input, output)).to be(false)
      truncated = File.join(directory, 'truncated.png')
      File.binwrite(truncated, File.binread(input, 12))
      expect(renderer.render('image/png', truncated, output)).to be(false)
      expect(File).not_to exist(output)
    end
  end

  it 'falls back for corrupt files without replacing the original' do
    Dir.mktmpdir do |directory|
      original = File.join(directory, 'broken.pdf')
      File.write(original, 'synthetic corrupt file')
      expect(renderer.render('application/pdf', original, File.join(directory, 'preview.jpg'))).to be(false)
      expect(File.read(original)).to eq('synthetic corrupt file')
    end
  end

  it 'does not execute converters for audio or active formats' do
    expect(renderer.render('image/svg+xml', '/absent.svg', '/absent.jpg')).to be(false)
    expect(renderer.render('audio/mpeg', '/absent.mp3', '/absent.jpg')).to be(false)
  end

  context 'with disguised input' do
    it 'rejects a playlist disguised as mp4 without reading its local media source' do
      Dir.mktmpdir do |directory|
        original = File.join(directory, 'playlist.mp4')
        media = File.expand_path('../../assets/sample.mp4', __dir__)
        File.write(original, "ffconcat version 1.0\nfile '#{media}'\n")
        output = File.join(directory, 'preview.jpg')
        expect(described_class.new.render('video/mp4', original, output)).to be(false)
        expect(File).not_to exist(output)
      end
    end
  end
end
