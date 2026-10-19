require 'rails_helper'

# #1426 (tema 4) — a foto mandada na criação vira material da base: o texto dela é lido pelo mesmo OCR do PDF escaneado
# e segue a revisão como qualquer arquivo. Os bytes são conferidos antes do OCR: o tesseract nunca recebe o que não é
# imagem (ele trata texto como lista de arquivos) nem uma bomba de pixels.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Foto do
  subject(:processor) { described_class.new(source) }

  let(:ocr) { Autonomia::Agents::Knowledge::Processors::Ocr }
  let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }
  let(:bytes) { png }
  # ActiveStorage delega #download dinamicamente (method_missing -> blob); verified double não o vê.
  let(:source) { double('source', reference: 'tabela.png', source_type: 'foto', file: file) } # rubocop:disable RSpec/VerifiedDoubles
  let(:file) { double('attachment', attached?: true, download: bytes) } # rubocop:disable RSpec/VerifiedDoubles

  # Cabeçalho PNG válido que declara largura × altura, sem os pixels.
  def png_declarando(largura, altura)
    ["\x89PNG\r\n\x1a\n", [13].pack('N'), 'IHDR', [largura, altura].pack('NN'), "\x08\x02\x00\x00\x00", "\x00" * 64].map(&:b).join
  end

  it 'is the processor of a foto source' do
    expect(Autonomia::Agents::Knowledge::Processors::Dispatcher.for(source)).to be_a(described_class)
  end

  it 'returns the text read from the photo by OCR' do
    allow(ocr).to receive(:ler).and_return("  Pastel R$ 8,00\nCaldo de cana R$ 6,00  \n")

    expect(processor.extract).to eq("Pastel R$ 8,00\nCaldo de cana R$ 6,00")
    expect(ocr).to have_received(:ler).with(a_string_ending_with('.png'))
  end

  it 'returns empty text for a photo without readable text (the ingestion marks it as not read)' do
    allow(ocr).to receive(:ler).and_return(" \n ")

    expect(processor.extract).to eq('')
  end

  context 'when the bytes are not a photo' do
    let(:bytes) { "/etc/passwd\n/root/.ssh/id_rsa\n" }

    it 'refuses before the OCR (text disguised as png never reaches tesseract)' do
      allow(ocr).to receive(:ler)

      expect { processor.extract }.to raise_error(described_class::ExtractionError, 'foto_invalida: tipo')
      expect(ocr).not_to have_received(:ler)
    end
  end

  context 'when the photo declares too many pixels' do
    let(:bytes) { png_declarando(14_000, 14_000) }

    it 'refuses the pixel bomb before the OCR' do
      allow(ocr).to receive(:ler)

      expect { processor.extract }.to raise_error(described_class::ExtractionError, 'foto_invalida: pixels')
      expect(ocr).not_to have_received(:ler)
    end
  end

  it 'fails as OCR unavailable when tesseract is missing or times out' do
    allow(ocr).to receive(:ler).and_raise(ocr::Indisponivel, 'tesseract_timeout')

    expect { processor.extract }.to raise_error(described_class::UnsupportedFormat, 'foto_ocr_unavailable')
  end

  it 'fails as not read when tesseract refuses the file' do
    allow(ocr).to receive(:ler).and_raise(ocr::Falhou, 'tesseract_exit_1')

    expect { processor.extract }.to raise_error(described_class::ExtractionError, 'foto_ocr_failed')
  end
end
