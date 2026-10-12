require 'rails_helper'

# Logo para fundo escuro gerada a partir da logo enviada (#1295). Precisa da libvips de verdade (a imagem de produção
# e o CI a instalam); onde ela não existe, o exemplo é marcado como pendente com o motivo.
RSpec.describe Crm::BookingV2::LogoDarkEngine, :aggregate_failures do
  before do
    require 'image_processing/vips'
  rescue LoadError => e
    skip "libvips indisponível nesta máquina: #{e.class}"
  end

  let(:navy) { [13, 35, 68] }
  let(:black) { [0, 0, 0] }
  let(:white) { [255, 255, 255] }

  # Tela de `width` x `height` na cor `fill` ([r, g, b] ou [r, g, b, a]) com retângulos `[cor, x, y, largura, altura]`.
  def canvas(fill, shapes, width: 120, height: 80)
    base = Vips::Image.black(width, height).new_from_image(fill).cast(:uchar).copy(interpretation: :srgb)
    shapes.reduce(base) { |image, (color, x, y, w, h)| image.draw_rect(color, x, y, w, h, fill: true) }
  end

  def transparent(shapes, **size)
    canvas([0, 0, 0, 0], shapes.map { |color, *box| [color + [255], *box] }, **size).pngsave_buffer
  end

  def pixel(outcome, left, top)
    Vips::Image.new_from_buffer(outcome.png, '').getpoint(left, top).map(&:round)
  end

  describe 'logo com transparência' do
    it 'escura e sem cor: gera a mesma logo em tons invertidos, com a transparência mantida' do
      outcome = described_class.call(transparent([[black, 20, 20, 80, 40], [[120, 120, 120], 30, 30, 20, 20]]))

      expect(outcome).to have_attributes(source: 'generated', reason: :inverted)
      expect(pixel(outcome, 90, 40)).to eq([255, 255, 255, 255])
      # O cinza de dentro continua cinza: o desenho interno não vira um bloco branco.
      expect(pixel(outcome, 40, 40)).to eq([135, 135, 135, 255])
      expect(pixel(outcome, 2, 2).last).to eq(0)
    end

    it 'escura e de uma cor só: gera a silhueta branca' do
      outcome = described_class.call(transparent([[navy, 20, 20, 80, 40]]))

      expect(outcome).to have_attributes(source: 'generated', reason: :silhouette)
      expect(pixel(outcome, 60, 40)).to eq([255, 255, 255, 255])
      expect(pixel(outcome, 2, 2).last).to eq(0)
    end

    it 'branca: já se lê no escuro, usa a mesma e não gera nada' do
      outcome = described_class.call(transparent([[white, 20, 20, 80, 40]]))

      expect(outcome).to have_attributes(source: 'same', png: nil, reason: :legible)
    end

    it 'colorida e clara: usa a mesma' do
      outcome = described_class.call(transparent([[[255, 200, 0], 10, 20, 50, 40], [[0, 200, 255], 60, 20, 50, 40]]))

      expect(outcome).to have_attributes(source: 'same', png: nil)
    end

    it 'colorida com parte escura: não vira silhueta, fica na placa' do
      outcome = described_class.call(transparent([[[220, 30, 30], 10, 20, 50, 40], [navy, 60, 20, 50, 40]]))

      expect(outcome).to have_attributes(source: 'plate', png: nil, reason: :several_colors)
    end

    it 'branca com um pedaço preto grande: inverter pioraria, fica na placa' do
      outcome = described_class.call(transparent([[white, 10, 20, 60, 40], [black, 70, 20, 40, 40]]))

      expect(outcome).to have_attributes(source: 'plate', png: nil, reason: :mixed_tones)
    end

    it 'PNG de 16 bits por canal: mesma decisão e mesma imagem que o de 8 bits' do
      eight = canvas([0, 0, 0, 0], [[navy + [255], 20, 20, 80, 40]])
      sixteen = (eight.cast(:ushort) * 257).cast(:ushort).copy(interpretation: :rgb16).pngsave_buffer(bitdepth: 16)
      outcome = described_class.call(sixteen)

      expect(Vips::Image.new_from_buffer(sixteen, '').format).to eq(:ushort)
      expect(outcome).to have_attributes(source: 'generated', reason: :silhouette)
      expect(pixel(outcome, 60, 40)).to eq([255, 255, 255, 255])
      expect(pixel(outcome, 2, 2).last).to eq(0)
    end

    it 'PNG em tons de cinza com transparência (2 canais): preto vira branco' do
      gray = Vips::Image.black(120, 80).bandjoin(0).cast(:uchar).copy(interpretation: :b_w)
                        .draw_rect([0, 255], 20, 20, 80, 40, fill: true).pngsave_buffer
      outcome = described_class.call(gray)

      expect(outcome).to have_attributes(source: 'generated', reason: :inverted)
      expect(pixel(outcome, 60, 40)).to eq([255, 255, 255, 255])
    end

    it 'imagem de 1 pixel não é logo: placa, sem passar pelo socorro de erro' do
      dot = Vips::Image.black(1, 1).bandjoin([0, 0, 255]).cast(:uchar).copy(interpretation: :srgb).pngsave_buffer

      expect(described_class.call(dot)).to have_attributes(source: 'plate', png: nil, reason: :too_small)
    end

    it 'toda transparente: placa' do
      expect(described_class.call(transparent([]))).to have_attributes(source: 'plate', reason: :empty)
    end
  end

  describe 'imagem sem transparência' do
    it 'PNG com fundo branco sólido e logo escura: tira o fundo (e o miolo da mesma cor) e gera a versão clara' do
      # Um "anel": retângulo azul-escuro com miolo branco, como o miolo de uma letra.
      png = canvas(white, [[navy, 20, 15, 80, 50], [white, 50, 30, 20, 20]]).pngsave_buffer
      outcome = described_class.call(png)

      expect(outcome).to have_attributes(source: 'generated', reason: :silhouette)
      expect(pixel(outcome, 30, 40)).to eq([255, 255, 255, 255])
      expect(pixel(outcome, 2, 2).last).to eq(0)
      expect(pixel(outcome, 60, 40).last).to eq(0)
    end

    it 'JPEG com fundo branco e logo preta: o ruído do JPEG não impede de tirar o fundo' do
      jpeg = canvas(white, [[black, 20, 15, 80, 50]]).jpegsave_buffer(Q: 70)
      outcome = described_class.call(jpeg)

      expect(outcome).to have_attributes(source: 'generated', reason: :inverted)
      expect(pixel(outcome, 60, 40).first(3)).to all(be >= 240)
      expect(pixel(outcome, 3, 3).last).to eq(0)
    end

    it 'logo clara sobre fundo sólido: gera a logo recortada, sem o fundo' do
      png = canvas(white, [[[255, 200, 0], 20, 15, 80, 50]]).pngsave_buffer
      outcome = described_class.call(png)

      expect(outcome).to have_attributes(source: 'generated', reason: :cutout)
      expect(pixel(outcome, 60, 40)).to eq([255, 200, 0, 255])
      expect(pixel(outcome, 2, 2).last).to eq(0)
    end

    it 'foto (JPEG sem fundo sólido): placa' do
      bands = Array.new(3) { Vips::Image.gaussnoise(160, 120, mean: 128, sigma: 60) }
      photo = bands.first.bandjoin(bands.drop(1)).cast(:uchar).jpegsave_buffer(Q: 85)

      expect(described_class.call(photo)).to have_attributes(source: 'plate', png: nil, reason: :no_transparency)
    end

    it 'JPEG chapado de uma cor só, sem desenho: tirando o fundo não sobra nada, placa' do
      flat = canvas([30, 90, 200], []).jpegsave_buffer

      expect(described_class.call(flat)).to have_attributes(source: 'plate', png: nil, reason: :empty)
    end

    it 'cantos iguais mas borda cortada pelo desenho: não é fundo sólido, placa' do
      png = canvas(white, [[navy, 20, 0, 80, 80], [[200, 30, 30], 0, 20, 120, 40]]).pngsave_buffer

      expect(described_class.call(png)).to have_attributes(source: 'plate', reason: :no_transparency)
    end
  end

  describe 'limites' do
    it 'imagem enorme é recusada pelo cabeçalho, sem abrir os pixels' do
      huge = Vips::Image.black(5000, 4000).cast(:uchar).pngsave_buffer(compression: 9)
      expect(huge.bytesize).to be < Crm::BookingPageSettings::MAX_IMAGE_BYTES
      allow(Vips::Image).to receive(:thumbnail_buffer).and_call_original

      expect(described_class.call(huge)).to have_attributes(source: 'plate', png: nil, reason: :too_large)
      expect(Vips::Image).not_to have_received(:thumbnail_buffer)
    end

    it 'imagem grande dentro do limite é reduzida: a gerada tem no máximo 800 px de lado' do
      big = transparent([[navy, 200, 200, 2000, 600]], width: 2400, height: 1000)
      outcome = described_class.call(big)
      image = Vips::Image.new_from_buffer(outcome.png, '')

      expect(outcome.source).to eq('generated')
      expect([image.width, image.height]).to eq([800, 333])
    end

    it 'arquivo corrompido ou que não é imagem: placa, sem erro' do
      expect(described_class.call('isto não é uma imagem')).to have_attributes(source: 'plate', png: nil, reason: :unreadable)
      truncated = transparent([[navy, 20, 20, 80, 40]]).byteslice(0, 60)
      expect(described_class.call(truncated)).to have_attributes(source: 'plate', png: nil, reason: :unreadable)
    end

    it 'o cartão escuro usado na conta é o do tema da página' do
      theme = Rails.root.join('app/javascript/public_booking_v2/assets/_booking-theme.scss').read
      expect(theme).to include("--bk-card: #{described_class::DARK_CARD.join(' ')};")
    end
  end
end
