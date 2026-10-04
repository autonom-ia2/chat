require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::VideoDoArtigo do
  let(:pasta) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.rm_rf(pasta) }

  def gravar(extensao, conteudo, quando = Time.zone.now)
    caminho = pasta.join("02.04.#{extensao}")
    File.binwrite(caminho, conteudo)
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

  describe 'duracao' do
    before { gravar('mp4', 'vídeo') }

    def duracao = described_class.para('02.04', pasta: pasta)['duracao']

    it 'é o fim da última legenda, com hora e configuração depois do tempo' do
      gravar('vtt', "WEBVTT\n\n1\n00:00:00.000 --> 00:00:03.000\nAbra o menu\n\n2\n00:00:03.000 --> 01:02:05.600 align:start\nPronto\n")

      expect(duracao).to eq(3726)
    end

    it 'aceita o tempo sem hora' do
      gravar('vtt', "WEBVTT\n\n00:00.000 --> 00:04.400\nAbra o menu\n\n00:04.400 --> 00:11.312\nPronto\n")

      expect(duracao).to eq(11)
    end

    # Legenda salva no Windows: marca de ordem no começo e \r\n no fim das linhas.
    it 'tolera BOM e quebra de linha \r\n' do
      gravar('vtt', "\xEF\xBB\xBFWEBVTT\r\n\r\n00:00:00.000 --> 00:00:08.751\r\nPronto\r\n")

      expect(duracao).to eq(9)
    end

    it 'fica nil sem legenda' do
      expect(duracao).to be_nil
    end

    it 'fica nil com tempo ilegível' do
      gravar('vtt', "WEBVTT\n\n00:00:00.000 --> depois\nPronto\n")

      expect(duracao).to be_nil
    end

    # A legenda lida uma vez dá a versão do endereço e a duração.
    it 'mantém o endereço da legenda junto com a duração' do
      gravar('vtt', "WEBVTT\n\n00:00.000 --> 00:04.400\nPronto\n")

      expect(described_class.para('02.04', pasta: pasta)['legenda']).to start_with('/central-de-ajuda/videos/02.04.vtt?v=')
    end
  end
end
