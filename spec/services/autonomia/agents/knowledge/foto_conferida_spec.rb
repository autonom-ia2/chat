require 'rails_helper'

# #1426 (revisão adversarial) — a foto é conferida pelos BYTES: tipo pelo conteúdo, até 5 MB e até 40 MP lidos do
# cabeçalho, sem decodificar a imagem.
RSpec.describe Autonomia::Agents::Knowledge::FotoConferida do
  let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }

  def png_declarando(largura, altura)
    ["\x89PNG\r\n\x1a\n", [13].pack('N'), 'IHDR', [largura, altura].pack('NN'), "\x08\x02\x00\x00\x00", "\x00" * 64].map(&:b).join
  end

  def jpeg_declarando(largura, altura)
    "\xFF\xD8\xFF\xE0".b + [16].pack('n') + "JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00".b +
      "\xFF\xC0".b + [17].pack('n') + "\x08".b + [altura, largura].pack('nn') + ("\x00" * 10) + "\xFF\xDA".b + ("\x00" * 48)
  end

  # GIF mínimo de verdade: tela, quadros (posição e tamanho, sem tabela de cores, dados LZW vazios) e o fim.
  def gif_com_quadros(largura, altura, quadros)
    blocos = quadros.map { |quadro| [',', quadro.pack('vvvv'), "\x00\x02\x01\x00\x00"].map(&:b).join }
    ['GIF89a', [largura, altura].pack('vv'), "\x00\x00\x00", *blocos, ';'].map(&:b).join
  end

  def gif_declarando(largura, altura)
    gif_com_quadros(largura, altura, [[0, 0, largura, altura]])
  end

  def vinte_e_quatro_bits(valor)
    [valor].pack('V').byteslice(0, 3)
  end

  # WebP com a marca de animação no VP8X e um pedaço ANIM.
  def webp_animado(largura, altura)
    vp8x = ['VP8X', [10].pack('V'), "\x02\x00\x00\x00", vinte_e_quatro_bits(largura - 1), vinte_e_quatro_bits(altura - 1)]
           .map(&:b).join
    anim = 'ANIM'.b + [6].pack('V') + ("\x00" * 6)
    "RIFF#{[4 + vp8x.bytesize + anim.bytesize].pack('V')}WEBP".b + vp8x + anim
  end

  def webp_declarando(largura, altura)
    vp8x = 'VP8X'.b + [10].pack('V') + ("\x00" * 4) + [largura - 1].pack('V').byteslice(0, 3) +
           [altura - 1].pack('V').byteslice(0, 3)
    "RIFF#{[4 + vp8x.bytesize].pack('V')}WEBP".b + vp8x + ("\x00" * 64)
  end

  it 'accepts a real photo' do
    expect(described_class.problema(png)).to be_nil
  end

  it 'refuses text, whatever the client declared' do
    expect(described_class.problema("Pastel R$ 8,00\n/etc/passwd\n")).to eq(:tipo)
  end

  it 'refuses a document that is not a photo' do
    expect(described_class.problema("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n")).to eq(:tipo)
  end

  it 'refuses a photo above 5 MB' do
    expect(described_class.problema(png + ("\x00" * Autonomia::Agents::Config::MAX_IMAGE_BYTES))).to eq(:tamanho)
  end

  { 'png' => :png_declarando, 'jpeg' => :jpeg_declarando, 'gif' => :gif_declarando, 'webp' => :webp_declarando }
    .each do |formato, montar|
      it "reads the #{formato} header: accepts 6000x6000 and refuses a 14000x14000 pixel bomb" do
        expect(described_class.problema(send(montar, 6000, 6000))).to be_nil
        expect(described_class.problema(send(montar, 14_000, 14_000))).to eq(:pixels)
      end
    end

  # X1 — animação e quadro maior que a tela.
  it 'refuses a GIF with more than one frame' do
    expect(described_class.problema(gif_com_quadros(100, 100, [[0, 0, 100, 100], [0, 0, 100, 100]]))).to eq(:animada)
  end

  it 'refuses a one-frame GIF whose frame is a pixel bomb behind a small screen' do
    expect(described_class.problema(gif_com_quadros(100, 100, [[0, 0, 14_000, 14_000]]))).to eq(:pixels)
    expect(described_class.problema(gif_com_quadros(100, 100, [[13_900, 13_900, 100, 100]]))).to eq(:pixels)
  end

  it 'refuses a GIF cut in the middle' do
    gif = gif_declarando(100, 100)
    expect(described_class.problema(gif.byteslice(0, gif.bytesize - 3))).to eq(:pixels)
  end

  it 'refuses an animated WebP' do
    expect(described_class.problema(webp_animado(100, 100))).to eq(:animada)
  end

  # V4 — fixtures de ataque, montadas em memória (nenhum binário no repositório).
  describe 'attack fixtures' do
    def pedaco_png(tipo, dados)
      [[dados.bytesize].pack('N'), tipo, dados, "\x00" * 4].map(&:b).join
    end

    def segmento_jpeg(marcador, dados)
      ["\xFF".b, marcador.chr.b, [dados.bytesize + 2].pack('n'), dados.b].join
    end

    def sof(largura, altura)
      segmento_jpeg(0xC0, "\x08".b + [altura, largura].pack('nn') + "\x01\x01\x11\x00".b)
    end

    def jpeg_com(*segmentos)
      "\xFF\xD8".b + segmentos.join.b + "\xFF\xDA".b + ("\x00" * 32)
    end

    def webp_com(*pedacos)
      corpo = pedacos.map { |tipo, dados| tipo.b + [dados.bytesize].pack('V') + dados.b }.join
      "RIFF#{[4 + corpo.bytesize].pack('V')}WEBP".b + corpo
    end

    describe 'PNG' do
      it 'refuses an IHDR that is not right after the signature' do
        ihdr = pedaco_png('IHDR', [[100, 100].pack('NN'), "\x08\x02\x00\x00\x00"].map(&:b).join)
        png = ["\x89PNG\r\n\x1a\n".b, pedaco_png('tEXt', 'abc'), ihdr].join

        expect(described_class.problema(png)).to eq(:pixels)
      end

      # O decodificador aloca pelo IHDR: dados a mais no IDAT não pedem mais memória, e o arquivo inteiro tem o teto de 5 MB.
      it 'goes by the IHDR when it lies small with a big IDAT, within the size ceiling' do
        png = png_declarando(100, 100) + pedaco_png('IDAT', "\x00" * 4.megabytes)
        expect(described_class.problema(png)).to be_nil

        expect(described_class.problema(png_declarando(100, 100) + pedaco_png('IDAT', "\x00" * 5.megabytes))).to eq(:tamanho)
      end
    end

    describe 'JPEG' do
      it 'stops on a segment of size 0 or 1 and refuses it' do
        [0, 1].each do |tamanho|
          jpeg = "\xFF\xD8\xFF\xE0".b + [tamanho].pack('n') + sof(100, 100) + "\xFF\xDA".b

          expect(described_class.problema(jpeg)).to eq(:pixels)
        end
      end

      it 'refuses more than one start of frame, in any order' do
        expect(described_class.problema(jpeg_com(sof(100, 100), sof(14_000, 14_000)))).to eq(:pixels)
        expect(described_class.problema(jpeg_com(sof(14_000, 14_000), sof(100, 100)))).to eq(:pixels)
      end

      it 'finds a late start of frame after big segments' do
        app = segmento_jpeg(0xE1, "\x00" * 60_000)

        expect(described_class.problema(jpeg_com(app, app, sof(6000, 6000)))).to be_nil
        expect(described_class.problema(jpeg_com(app, app, sof(14_000, 14_000)))).to eq(:pixels)
      end

      it 'refuses a JPEG cut before the image data' do
        expect(described_class.problema("\xFF\xD8".b + sof(100, 100))).to eq(:pixels)
      end
    end

    describe 'GIF' do
      it 'reads the frame after an extension block' do
        extensao = "\x21\xF9\x04\x00\x00\x00\x00\x00".b
        gif = ->(largura) { gif_com_quadros(100, 100, [[0, 0, largura, largura]]).sub(',', "#{extensao},") }

        expect(described_class.problema(gif.call(100))).to be_nil
        expect(described_class.problema(gif.call(14_000))).to eq(:pixels)
      end
    end

    describe 'WebP' do
      it 'refuses a lossy (VP8) 16383 x 16383' do
        vp8 = "\x00\x00\x00\x9D\x01\x2A".b + [16_383, 16_383].pack('vv') + ("\x00" * 20)

        expect(described_class.problema(webp_com(['VP8 ', vp8]))).to eq(:pixels)
      end

      it 'refuses a lossless (VP8L) 16383 x 16383' do
        vp8l = "\x2F".b + [16_382 | (16_382 << 14)].pack('V') + ("\x00" * 20)

        expect(described_class.problema(webp_com(['VP8L', vp8l]))).to eq(:pixels)
      end

      it 'refuses a VP8X without the animation flag that carries an ANMF frame' do
        vp8x = "\x00\x00\x00\x00".b + vinte_e_quatro_bits(99) + vinte_e_quatro_bits(99)

        expect(described_class.problema(webp_com(['VP8X', vp8x], ['ANMF', "\x00" * 16]))).to eq(:animada)
      end
    end

    describe 'size' do
      it 'refuses an empty file' do
        expect(described_class.problema('')).to eq(:tipo)
      end

      it 'accepts exactly 5 MB and refuses one byte more' do
        teto = Autonomia::Agents::Config::MAX_IMAGE_BYTES
        no_teto = png_declarando(100, 100) + pedaco_png('IDAT', '')
        no_teto += "\x00" * (teto - no_teto.bytesize)

        expect(described_class.problema(no_teto)).to be_nil
        expect(described_class.problema("#{no_teto}\x00".b)).to eq(:tamanho)
      end
    end
  end
end
