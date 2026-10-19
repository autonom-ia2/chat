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

  def gif_declarando(largura, altura)
    'GIF89a'.b + [largura, altura].pack('vv') + ("\x00" * 64)
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
end
