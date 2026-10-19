require 'rails_helper'

RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  subject(:processor) { described_class.new(source) }

  # ActiveStorage delega #download dinamicamente (method_missing -> blob); verified double não o vê.
  let(:source) { double('source', reference: 'doc.pdf', source_type: 'pdf', file: file) } # rubocop:disable RSpec/VerifiedDoubles
  let(:file) { double('attachment', attached?: true, download: 'pdf-bytes') } # rubocop:disable RSpec/VerifiedDoubles
  let(:reader) { instance_double(PDF::Reader) }

  # Padrão: A4 em pontos (72 por polegada), que a 300 DPI dá 8,7 MP.
  def stub_pages(page_texts, tamanho: { width: 595, height: 842 })
    pages = page_texts.map { |text| instance_double(PDF::Reader::Page, text: text, **tamanho) }
    allow(PDF::Reader).to receive(:new).and_return(reader)
    allow(reader).to receive(:pages).and_return(pages)
  end

  describe '#extract' do
    let(:rasterizacao) { Autonomia::Agents::Knowledge::Processors::Rasterizacao }
    let(:ocr) { Autonomia::Agents::Knowledge::Processors::Ocr }

    it 'concatenates the text of every page for a text-layer PDF' do
      # Arrange
      stub_pages(['Primeira pagina com bastante texto', 'Segunda pagina tambem'])

      # Act
      result = processor.extract

      # Assert
      expect(result).to include('Primeira pagina com bastante texto')
      expect(result).to include('Segunda pagina tambem')
    end

    context 'when the text layer is near-empty (scanned PDF)' do
      let(:account) { create(:account) }
      let(:source) { double('source', reference: 'doc.pdf', source_type: 'pdf', file: file, account: account) } # rubocop:disable RSpec/VerifiedDoubles

      before { Autonomia::Agents::Fase2.ligar!(account) }

      # Stub da pilha de OCR (Rasterizacao + Ocr) p/ não exigir binários; os dois têm spec próprio com binário falso.
      def stub_ocr(text)
        allow(rasterizacao).to receive(:pagina) { |_pdf, indice, &bloco| bloco.call("/tmp/pagina-#{indice}.png") }
        allow(ocr).to receive(:ler).and_return(text)
      end

      it 'rasterizes each page of the downloaded file and returns the OCR text' do
        # Arrange
        stub_pages([' ', ' ']) # abaixo de OCR_MIN_CHARS -> dispara OCR
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')

        # Act
        result = processor.extract

        # Assert
        expect(result).to eq("TEXTO RECONHECIDO VIA OCR DO SCAN\nTEXTO RECONHECIDO VIA OCR DO SCAN")
        expect(rasterizacao).to have_received(:pagina).with(a_string_ending_with('.pdf'), 0)
        expect(rasterizacao).to have_received(:pagina).with(a_string_ending_with('.pdf'), 1)
        expect(ocr).to have_received(:ler).with('/tmp/pagina-1.png')
        expect(file).to have_received(:download).once
      end

      # X2 — página que a 300 DPI passaria de 40 MP (A0) nem é rasterizada.
      it 'skips a page whose MediaBox at 300 DPI goes over the pixel ceiling' do
        # Arrange
        stub_pages([' '], tamanho: { width: 2384, height: 3370 })
        stub_ocr('nunca')
        allow(Rails.logger).to receive(:warn)

        # Act
        result = processor.extract

        # Assert
        expect(result).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
        expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_paginas_de_fora alem_do_teto=0 grandes=1/)
      end

      it 'returns the empty text gracefully when the OCR stack is unavailable' do
        # Arrange
        stub_pages(['']) # dispara OCR
        allow(rasterizacao).to receive(:pagina).and_raise(rasterizacao::Falhou, 'imagemagick_ausente')
        allow(Rails.logger).to receive(:warn)

        # Act
        result = processor.extract

        # Assert
        expect(result.strip).to eq('')
        expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_unavailable/)
      end

      it 'keeps the original text when OCR also yields near-empty output' do
        # Arrange
        stub_pages(['x'])
        stub_ocr('  ')

        # Act
        result = processor.extract

        # Assert — OCR quase-vazio: devolve o texto original bruto (extração normal não é stripada)
        expect(result).to eq("x\n")
      end

      # Fora do piloto, nada muda: o OCR não roda e o resultado é o de antes (texto original e o aviso no log).
      it 'does not run the OCR outside the Fase 2' do
        # Arrange
        Autonomia::Agents::Fase2.desligar!(account)
        stub_pages([' '])
        stub_ocr('nunca')
        allow(Rails.logger).to receive(:warn)

        # Act
        result = processor.extract

        # Assert
        expect(result).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
        expect(Rails.logger).to have_received(:warn).with('[autonomia] pdf_ocr_unavailable: fora_da_fase2')
      end

      it 'reads only up to the page ceiling and logs the pages left out' do
        # Arrange
        stub_const("#{described_class}::MAX_PAGINAS_OCR", 2)
        stub_pages([' ', ' ', ' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
        allow(Rails.logger).to receive(:warn)

        # Act
        processor.extract

        # Assert
        expect(rasterizacao).to have_received(:pagina).twice
        expect(rasterizacao).not_to have_received(:pagina).with(anything, 2)
        expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_paginas_de_fora alem_do_teto=1 grandes=$/)
      end

      # O que ficou de fora vai para o metadata do material (o PR 2 avisa o dono) e some quando nada fica de fora.
      context 'with a material of the base' do
        let(:agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support') }
        let(:source) do
          material = agente.sources.new(account: account, source_type: 'pdf', reference: 'manual.pdf')
          material.file.attach(io: StringIO.new('pdf-bytes'), filename: 'manual.pdf', content_type: 'application/pdf')
          material.save!
          material
        end

        it 'records the pages left out in the metadata, and clears it when none is left out' do
          stub_const("#{described_class}::MAX_PAGINAS_OCR", 1)
          stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
          stub_pages([' ', ' '])

          described_class.new(source).extract
          expect(source.reload.metadata['ocr_paginas_de_fora'])
            .to eq('teto' => 1, 'alem_do_teto' => 1, 'grandes' => [])

          stub_pages([' '])
          described_class.new(source).extract
          expect(source.reload.metadata).not_to have_key('ocr_paginas_de_fora')
        end
      end

      it 'does not run the OCR when the caller turned it off (attendance)' do
        # Arrange
        stub_pages([' '])
        stub_ocr('nunca')

        # Act
        result = described_class.new(source, ocr: false).extract

        # Assert
        expect(result).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
      end
    end

    it 'raises ExtractionError on a malformed PDF' do
      # Arrange
      allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError.new('boom'))

      # Act / Assert
      expect { processor.extract }.to raise_error(described_class::ExtractionError, /pdf_parse_failed/)
    end
  end
end
