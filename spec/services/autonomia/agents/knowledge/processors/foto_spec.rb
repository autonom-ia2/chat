require 'rails_helper'

# #1426 (tema 4) — a foto mandada na criação vira material da base: o texto dela é lido pelo mesmo OCR
# do PDF escaneado (rtesseract, pt-BR) e segue a revisão como qualquer arquivo.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Foto do
  subject(:processor) { described_class.new(source) }

  # ActiveStorage delega #download dinamicamente (method_missing -> blob); verified double não o vê.
  let(:source) { double('source', reference: 'tabela.jpg', source_type: 'foto', file: file) } # rubocop:disable RSpec/VerifiedDoubles
  let(:file) { double('attachment', attached?: true, download: 'jpg-bytes') } # rubocop:disable RSpec/VerifiedDoubles

  it 'is the processor of a foto source' do
    expect(Autonomia::Agents::Knowledge::Processors::Dispatcher.for(source)).to be_a(described_class)
  end

  it 'returns the text read from the photo by OCR, in Portuguese' do
    # Arrange
    rtesseract = instance_double(RTesseract, to_s: "  Pastel R$ 8,00\nCaldo de cana R$ 6,00  \n")
    allow(RTesseract).to receive(:new).and_return(rtesseract)

    # Act
    result = processor.extract

    # Assert
    expect(result).to eq("Pastel R$ 8,00\nCaldo de cana R$ 6,00")
    expect(RTesseract).to have_received(:new).with(a_string_ending_with('.jpg'), lang: 'por')
  end

  it 'returns empty text for a photo without readable text (the ingestion marks it as not read)' do
    # Arrange
    allow(RTesseract).to receive(:new).and_return(instance_double(RTesseract, to_s: " \n "))

    # Act / Assert
    expect(processor.extract).to eq('')
  end

  it 'fails clearly when the OCR library is not available' do
    # Arrange
    allow(Autonomia::Agents::Knowledge::Processors::Ocr).to receive(:ler).and_raise(LoadError)

    # Act / Assert
    expect { processor.extract }.to raise_error(described_class::UnsupportedFormat, 'foto_ocr_unavailable')
  end
end
