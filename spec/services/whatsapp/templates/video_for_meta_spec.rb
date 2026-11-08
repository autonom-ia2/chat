require 'rails_helper'

# #2370: o WhatsApp só entrega vídeo MP4 com H.264 e AAC até 16 MB; a gravação do iPhone sai em HEVC, muitas vezes .mov.
# Vídeos de verdade, gerados pelo ffmpeg (o mesmo que a imagem de produção e a CI trazem).
RSpec.describe Whatsapp::Templates::VideoForMeta, :aggregate_failures do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  # `source`: size (640x360), duration (2 s) e audio (true).
  def video(name, codec:, extra: [], **source)
    path = File.join(dir, name)
    duration = source.fetch(:duration, 2)
    sound = source.fetch(:audio, true) ? ['-f', 'lavfi', '-i', "sine=frequency=440:duration=#{duration}", '-c:a', 'aac'] : []
    system('ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', "testsrc=size=#{source.fetch(:size, '640x360')}:rate=30:duration=#{duration}",
           *sound, '-c:v', codec, '-pix_fmt', 'yuv420p', *extra, '-shortest', path, exception: true)
    path
  end

  def upload(path, type)
    Rack::Test::UploadedFile.new(path, type)
  end

  def converted(path, name = File.basename(path))
    described_class.open_converted(path, name) do |media|
      yield media
      media
    end
  end

  describe '.ready' do
    it 'MP4 em H.264 e AAC já serve: segue o próprio arquivo, sem converter' do
      file = upload(video('pronto.mp4', codec: 'libx264'), 'video/mp4')

      media = described_class.ready(file, 'video/mp4')

      expect(media.io).to be(file)
      expect(media).to have_attributes(file_name: 'pronto.mp4', content_type: 'video/mp4')
    end

    it 'MP4 em H.264 sem áudio também serve' do
      file = upload(video('mudo.mp4', codec: 'libx264', audio: false), 'video/mp4')

      expect(described_class.ready(file, 'video/mp4').io).to be(file)
    end

    it 'HEVC, .mov ou H.264 de 10 bits: nil (vai para a conversão)' do
      hevc = upload(video('tela.mp4', codec: 'libx265', extra: %w[-tag:v hvc1]), 'video/mp4')
      mov = upload(video('IMG_0001.MOV', codec: 'libx264', extra: %w[-f mov]), 'video/quicktime')
      ten_bit = upload(video('dez.mp4', codec: 'libx264', extra: %w[-pix_fmt yuv420p10le]), 'video/mp4')

      expect(described_class.probe(ten_bit.path)).to include(video: 'h264', pix_fmt: 'yuv420p10le')
      expect([hevc, mov, ten_bit].map { |file| described_class.ready(file, file.content_type) }).to eq([nil, nil, nil])
    end

    it 'arquivo que não é vídeo (foto, PDF) segue sem passar pelo ffmpeg' do
      file = upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
      allow(Open3).to receive(:popen3)

      media = described_class.ready(file, 'image/png')

      expect(media).to have_attributes(io: file, content_type: 'image/png')
      expect(Open3).not_to have_received(:popen3)
    end

    it 'arquivo com tipo de vídeo que o ffprobe não lê: recusa com video_unreadable' do
      path = File.join(dir, 'falso.mp4')
      File.write(path, 'não sou vídeo')

      expect { described_class.ready(upload(path, 'video/mp4'), 'video/mp4') }
        .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq('video_unreadable') }
    end

    it 'vídeo acima de 100 MB: recusa com video_too_large sem ler o arquivo' do
      file = upload(video('grande.mp4', codec: 'libx264'), 'video/mp4')
      allow(file).to receive(:size).and_return(described_class::INPUT_MAX + 1)
      allow(Open3).to receive(:popen3)

      expect { described_class.ready(file, 'video/mp4') }
        .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq('video_too_large') }
      expect(Open3).not_to have_received(:popen3)
    end
  end

  describe '.open_converted' do
    it '.mov do iPhone em HEVC: vira MP4 em H.264 4:2:0 e AAC, com nome .mp4; o temporário é apagado no fim' do
      media = converted(video('IMG_0001.MOV', codec: 'libx265', extra: %w[-tag:v hvc1 -f mov])) do |ready|
        expect(ready).to have_attributes(file_name: 'IMG_0001.mp4', content_type: 'video/mp4')
        expect(described_class.probe(ready.io.path)).to include(video: 'h264', pix_fmt: 'yuv420p', audio: 'aac')
      end

      expect(media.io.path).to be_nil
    end

    it 'vídeo sem áudio: converte só o vídeo' do
      converted(video('mudo.mov', codec: 'libx265', audio: false, extra: %w[-f mov])) do |ready|
        expect(described_class.probe(ready.io.path)).to include(video: 'h264', audio: nil)
      end
    end

    it 'vídeo longo: o bitrate da duração mantém o resultado em 16 MB, com a mesma duração' do
      path = video('longo.mp4', codec: 'libx264', size: '1280x720', duration: 90, extra: %w[-preset ultrafast -b:v 4000k])
      expect(described_class.video_kbps(90)).to be < described_class::MAX_VIDEO_KBPS

      converted(path) do |ready|
        expect(ready.size).to be <= described_class::OUTPUT_MAX
        expect(described_class.probe(ready.io.path)[:duration]).to be_within(1).of(90)
      end
    end

    it 'erro dentro do bloco (a Meta recusou): o temporário é apagado mesmo assim' do
      media = nil
      expect do
        described_class.open_converted(video('erro.mov', codec: 'libx265', extra: %w[-f mov]), 'erro.mov') do |ready|
          media = ready
          raise Whatsapp::Templates::Manager::Refused, 'media_invalid'
        end
      end.to raise_error(Whatsapp::Templates::Manager::Refused)
      expect(media.io.path).to be_nil
    end
  end

  it 'o bitrate sai da duração para caber em 16 MB; longo demais recusa com video_too_long' do
    expect(described_class.video_kbps(10)).to eq(described_class::MAX_VIDEO_KBPS)
    expect(described_class.video_kbps(120)).to be_between(described_class::MIN_VIDEO_KBPS, 1000)
    expect { described_class.video_kbps(1200) }
      .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq('video_too_long') }
  end

  describe '.run' do
    it 'passou do tempo: mata o processo e recusa com video_unreadable' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { described_class.run(1, 'sleep', '30') }
        .to raise_error(described_class::Invalid) { |error| expect(error.code).to eq('video_unreadable') }
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
    end

    it 'processo que falha ou não existe: recusa com video_unreadable' do
      expect { described_class.run(5, 'false') }.to raise_error(described_class::Invalid)
      expect { described_class.run(5, 'ffmpeg-que-nao-existe') }.to raise_error(described_class::Invalid)
    end
  end
end
