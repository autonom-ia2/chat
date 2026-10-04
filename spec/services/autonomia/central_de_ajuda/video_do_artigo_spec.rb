require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::VideoDoArtigo do
  let(:pasta) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.rm_rf(pasta) }

  def gravar(extensao, conteudo, quando)
    caminho = pasta.join("02.04.#{extensao}")
    File.write(caminho, conteudo)
    File.utime(quando.to_time, quando.to_time, caminho)
  end

  it 'não tem vídeo sem o .mp4' do
    gravar('vtt', 'legenda', Time.zone.now)

    expect(described_class.para('02.04', pasta: pasta)).to be_nil
  end

  # O servidor entrega public/ com cache de um ano: o endereço precisa mudar quando o vídeo é regravado.
  it 'muda o endereço quando o vídeo é regravado com o mesmo nome' do
    gravar('mp4', 'vídeo antigo', 1.day.ago)
    antes = described_class.para('02.04', pasta: pasta)

    gravar('mp4', 'vídeo regravado', Time.zone.now)
    depois = described_class.para('02.04', pasta: pasta)

    expect(antes['arquivo']).to start_with('/central-de-ajuda/videos/02.04.mp4?v=')
    expect(depois['arquivo']).not_to eq(antes['arquivo'])
  end

  it 'mantém o endereço enquanto o arquivo não muda' do
    gravar('mp4', 'vídeo', 1.day.ago)
    primeira = described_class.para('02.04', pasta: pasta)
    segunda = described_class.para('02.04', pasta: pasta)

    expect(segunda).to eq(primeira)
  end
end
