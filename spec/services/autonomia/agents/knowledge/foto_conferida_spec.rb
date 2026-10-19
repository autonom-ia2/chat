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
      "\xFF\xC0".b + [17].pack('n') + "\x08".b + [altura, largura].pack('nn') + ("\x00" * 64)
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
end
