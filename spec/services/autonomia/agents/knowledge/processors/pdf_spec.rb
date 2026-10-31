require 'rails_helper'

RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  subject(:processor) { described_class.new(source) }

  # ActiveStorage delega #download dinamicamente (method_missing -> blob); verified double não o vê.
  let(:source) { double('source', reference: 'doc.pdf', source_type: 'pdf', file: file) } # rubocop:disable RSpec/VerifiedDoubles
  let(:file) { double('attachment', attached?: true, download: 'pdf-bytes') } # rubocop:disable RSpec/VerifiedDoubles
  let(:reader) { instance_double(PDF::Reader) }
  let(:account) { create(:account) }
  let(:rasterizacao) { Autonomia::Agents::Knowledge::Processors::Rasterizacao }
  let(:ocr) { Autonomia::Agents::Knowledge::Processors::Ocr }
  let(:a4) { '/MediaBox [0 0 595 842]' }
  let(:pdf_ocr) { Autonomia::Agents::Knowledge::Processors::PdfOcr }

  # Padrão: A4 em pontos (72 por polegada), que a 300 DPI dá 8,7 MP.
  def stub_pages(page_texts, caixa: [0, 0, 595, 842], attributes: {})
    objetos = instance_double(PDF::Reader::ObjectHash)
    allow(objetos).to receive(:deref) { |valor| valor }
    atributos = { MediaBox: caixa }.merge(attributes)
    pages = page_texts.map { |text| instance_double(PDF::Reader::Page, runs: [], text: text, attributes: atributos, objects: objetos) }
    allow(PDF::Reader).to receive(:new).and_return(reader)
    allow(reader).to receive(:pages).and_return(pages)
  end

  # Stub da pilha de OCR (Rasterizacao + Ocr) p/ não exigir binários; os dois têm spec próprio com binário falso.
  def stub_ocr(text)
    allow(rasterizacao).to receive(:pagina) { |_pdf, indice, &bloco| bloco.call("/tmp/pagina-#{indice}.png") }
    allow(ocr).to receive(:ler).and_return(text)
  end

  def material(**atributos)
    double('source', reference: 'doc.pdf', source_type: 'pdf', file: file, account: account, **atributos).tap do |fonte| # rubocop:disable RSpec/VerifiedDoubles
      allow(fonte).to receive(:paginas_de_fora=)
    end
  end

  # PDF de verdade, montado em memória com a tabela xref certa: `paginas` são os atributos de cada página, `pai` os do
  # nó /Pages (herdados), `antes` o que vem antes do cabeçalho, `extras` objetos depois das páginas (para referência
  # indireta: com uma página, o primeiro extra é "4 0 R").
  def pdf_em_memoria(paginas, pai: '', antes: '', extras: [])
    ids = paginas.each_index.map { |indice| indice + 3 }
    objetos = ['<< /Type /Catalog /Pages 2 0 R >>',
               "<< /Type /Pages /Kids [#{ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{paginas.size} #{pai} >>",
               *paginas.map { |atributos| "<< /Type /Page /Parent 2 0 R #{atributos} >>" }, *extras]
    corpo = "#{antes}%PDF-1.7\n"
    posicoes = objetos.each_with_index.map do |objeto, indice|
      corpo.bytesize.tap { corpo << "#{indice + 1} 0 obj\n#{objeto}\nendobj\n" }
    end
    "#{corpo}#{tabela_xref(posicoes, corpo.bytesize)}"
  end

  def tabela_xref(posicoes, inicio)
    linhas = posicoes.map { |posicao| format("%010d 00000 n \n", posicao) }.join
    "xref\n0 #{posicoes.size + 1}\n0000000000 65535 f \n#{linhas}" \
      "trailer\n<< /Size #{posicoes.size + 1} /Root 1 0 R >>\nstartxref\n#{inicio}\n%%EOF\n"
  end

  describe '#extract' do
    it 'concatenates the text of every page for a text-layer PDF' do
      stub_pages(['Primeira pagina com bastante texto', 'Segunda pagina tambem'])

      result = processor.extract

      expect(result).to include('Primeira pagina com bastante texto')
      expect(result).to include('Segunda pagina tambem')
    end

    # V3 — na Fase 2 a extração de texto tem teto de páginas; fora dela, como na main.
    describe 'the page ceiling of the text layer' do
      let(:source) { material }

      before do
        stub_const("#{described_class}::MAX_PAGINAS_TEXTO", 2)
        stub_pages(['Primeira pagina com bastante texto', 'Segunda pagina com bastante texto', 'Terceira pagina'])
      end

      it 'reads only up to the ceiling in the Fase 2 and records what was left out' do
        Autonomia::Agents::Fase2.ligar!(account)

        result = processor.extract

        expect(result).not_to include('Terceira')
        expect(source).to have_received(:paginas_de_fora=).with('texto_teto' => 2, 'texto_alem_do_teto' => 1, 'paginas_total' => 3)
      end

      it 'reads every page outside the Fase 2' do
        expect(processor.extract).to include('Terceira')
        expect(source).not_to have_received(:paginas_de_fora=)
      end
    end

    context 'when the text layer is near-empty (scanned PDF)' do
      let(:source) { material }

      before { Autonomia::Agents::Fase2.ligar!(account) }

      it 'rasterizes each page of the downloaded file and returns the OCR text' do
        stub_pages([' ', ' ']) # abaixo de OCR_MIN_CHARS -> dispara OCR
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')

        result = processor.extract

        expect(result).to eq("TEXTO RECONHECIDO VIA OCR DO SCAN\nTEXTO RECONHECIDO VIA OCR DO SCAN")
        expect(rasterizacao).to have_received(:pagina).with(a_string_ending_with('.pdf'), 0, tempo: 60)
        expect(rasterizacao).to have_received(:pagina).with(a_string_ending_with('.pdf'), 1, tempo: 60)
        expect(ocr).to have_received(:ler).with('/tmp/pagina-1.png', tempo: 60)
        expect(file).to have_received(:download).once
        expect(source).not_to have_received(:paginas_de_fora=)
      end

      # #1426 (PDF Suhai) — a conferência precisa saber que o texto veio de leitura de imagem.
      it 'marks the source as read by OCR when the OCR text is used' do
        allow(source).to receive(:leitura_de_imagem=)
        stub_pages([' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')

        processor.extract

        expect(source).to have_received(:leitura_de_imagem=).with(true)
      end

      # X2 — página que a 300 DPI passaria de 40 MP (A0) nem é rasterizada.
      it 'skips a page whose MediaBox at 300 DPI goes over the pixel ceiling' do
        stub_pages([' '], caixa: [0, 0, 2384, 3370])
        stub_ocr('nunca')
        allow(Rails.logger).to receive(:warn)

        expect(processor.extract).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
        expect(Rails.logger).to have_received(:warn).with(/pdf_paginas_de_fora .*"ocr_grandes":\[1\]/)
      end

      # V2 — a /UserUnit multiplica o tamanho da página: um A4 com UserUnit 3 passa de 40 MP.
      it 'multiplies the page size by the UserUnit' do
        stub_pages([' '], attributes: { UserUnit: 3 })
        stub_ocr('nunca')

        processor.extract

        expect(rasterizacao).not_to have_received(:pagina)
        expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_grandes' => [1]))
      end

      it 'returns the empty text gracefully when the OCR stack is unavailable' do
        stub_pages([''])
        allow(rasterizacao).to receive(:pagina).and_raise(rasterizacao::Falhou, 'imagemagick_ausente')
        allow(Rails.logger).to receive(:warn)

        expect(processor.extract.strip).to eq('')
        expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_unavailable/)
      end

      it 'returns the empty text when tesseract is missing or fails' do
        stub_pages([''])
        stub_ocr('x')
        allow(ocr).to receive(:ler).and_raise(ocr::Indisponivel, 'tesseract_ausente')

        expect(processor.extract.strip).to eq('')

        allow(ocr).to receive(:ler).and_raise(ocr::Falhou, 'tesseract_exit_1')
        expect(processor.extract.strip).to eq('')
      end

      # Uma página que o ImageMagick ou o tesseract recusa é pulada; as outras entram e a recusada vai para o aviso.
      it 'skips a page that fails and keeps the others' do
        stub_pages([' ', ' ', ' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
        allow(rasterizacao).to receive(:pagina).with(anything, 1, tempo: anything).and_raise(rasterizacao::Falhou, 'imagemagick_exit_1')
        allow(ocr).to receive(:ler).with('/tmp/pagina-2.png', tempo: anything).and_raise(ocr::Falhou, 'tesseract_exit_1')
        allow(Rails.logger).to receive(:warn)

        expect(processor.extract).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
        expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_falhou' => [2, 3]))
        expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_pagina_falhou pagina=2 /)
        expect(Rails.logger).not_to have_received(:warn).with(/pdf_ocr_unavailable/)
      end

      # Q4 — o tesseract que estoura o tempo numa página é falha DAQUELA página: ela é pulada, as outras seguem.
      it 'skips a page whose tesseract timed out' do
        stub_pages([' ', ' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
        allow(ocr).to receive(:ler).with('/tmp/pagina-0.png', tempo: anything).and_raise(ocr::Falhou, 'tesseract_timeout')

        expect(processor.extract).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
        expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_falhou' => [1]))
      end

      it 'keeps the behavior of today when every page fails: original text and the same warning' do
        stub_pages([' ', ' '])
        allow(rasterizacao).to receive(:pagina).and_raise(rasterizacao::Falhou, 'imagemagick_exit_1')
        allow(Rails.logger).to receive(:warn)

        expect(processor.extract).to eq(" \n \n")
        expect(rasterizacao).to have_received(:pagina).twice
        expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_unavailable: .*imagemagick_exit_1/)
        # P2 — e o dono fica sabendo quais páginas falharam.
        expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_falhou' => [1, 2]))
      end

      # Sem o tesseract nenhuma página vai funcionar: para na primeira.
      it 'stops at the first page when tesseract is missing' do
        stub_pages([' ', ' '])
        stub_ocr('x')
        allow(ocr).to receive(:ler).and_raise(ocr::Indisponivel, 'tesseract_missing')

        expect(processor.extract).to eq(" \n \n")
        expect(rasterizacao).to have_received(:pagina).once
        expect(source).not_to have_received(:paginas_de_fora=)
      end

      # K3 — erro que não é de PDF ruim nem de binário é bug: vai ao Sentry e sobe.
      it 'sends an unexpected error to the tracker and raises it' do
        stub_pages([''])
        stub_ocr('x')
        allow(ocr).to receive(:ler).and_raise(NoMethodError, 'bug')
        tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

        expect { processor.extract }.to raise_error(NoMethodError, 'bug')
        expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(NoMethodError), account: account)
        expect(tracker).to have_received(:capture_exception)
      end

      it 'keeps the original text when OCR also yields near-empty output' do
        stub_pages(['x'])
        stub_ocr('  ')

        # OCR quase-vazio: devolve o texto original bruto (extração normal não é stripada)
        expect(processor.extract).to eq("x\n")
      end

      # Fora do piloto, nada muda: o OCR não roda e o resultado é o de antes (texto original e o aviso no log).
      it 'does not run the OCR outside the Fase 2' do
        Autonomia::Agents::Fase2.desligar!(account)
        stub_pages([' '])
        stub_ocr('nunca')
        allow(Rails.logger).to receive(:warn)

        expect(processor.extract).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
        expect(Rails.logger).to have_received(:warn).with('[autonomia] pdf_ocr_unavailable: fora_da_fase2')
      end

      # K2 — a Lia (instrução mantida) fica como na main: sem OCR de PDF.
      it 'does not run the OCR for the Lia' do
        lia = described_class.new(material(agent: instance_double(Autonomia::Agents::Agent, instrucao_mantida?: true)))
        stub_pages([' '])
        stub_ocr('nunca')
        allow(Rails.logger).to receive(:warn)

        expect(lia.extract).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
        expect(Rails.logger).to have_received(:warn).with('[autonomia] pdf_ocr_unavailable: agente_protegido')
      end

      it 'runs the OCR for an agent of the Fase 2 that is not the Lia' do
        bia = described_class.new(material(agent: instance_double(Autonomia::Agents::Agent, instrucao_mantida?: false)))
        stub_pages([' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')

        expect(bia.extract).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
      end

      it 'reads only up to the page ceiling and records the pages left out' do
        stub_const("#{pdf_ocr}::MAX_PAGINAS_OCR", 2)
        stub_pages([' ', ' ', ' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')

        processor.extract

        expect(rasterizacao).to have_received(:pagina).twice
        expect(rasterizacao).not_to have_received(:pagina).with(anything, 2, any_args)
        expect(source).to have_received(:paginas_de_fora=)
          .with('ocr_teto' => 2, 'ocr_alem_do_teto' => 1, 'ocr_grandes' => [], 'ocr_prazo' => [], 'ocr_falhou' => [],
                'paginas_total' => 3)
      end

      # K4 — o OCR do PDF tem prazo total; as páginas que não couberam vão para o aviso com o motivo `prazo`.
      it 'stops at the total deadline and records the pages not read' do
        stub_pages([' ', ' ', ' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
        relogio = 0
        allow(pdf_ocr).to receive(:agora) { relogio }
        allow(ocr).to receive(:ler) do
          relogio += described_class::PRAZO_OCR + 1
          'TEXTO RECONHECIDO VIA OCR DO SCAN'
        end

        expect(processor.extract).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
        expect(rasterizacao).to have_received(:pagina).once
        expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_prazo' => [2, 3]))
      end

      # Q3 — cada página recebe o menor entre o seu tempo máximo e o que resta do prazo: a soma nunca passa dele.
      it 'gives each page at most the time left in the deadline' do
        stub_pages([' ', ' '])
        stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
        relogio = 0
        allow(pdf_ocr).to receive(:agora) { relogio }
        allow(rasterizacao).to receive(:pagina) do |_pdf, indice, **, &bloco|
          relogio = 250 if indice.zero?
          bloco.call("/tmp/pagina-#{indice}.png")
        end

        processor.extract

        expect(rasterizacao).to have_received(:pagina).with(anything, 0, tempo: 60)
        expect(ocr).to have_received(:ler).with('/tmp/pagina-0.png', tempo: 50)
        expect(rasterizacao).to have_received(:pagina).with(anything, 1, tempo: 50)
      end

      # Q6 — o PDF temporário some também quando a leitura quebra.
      it 'removes the temporary PDF when the reading breaks' do
        stub_pages([' '])
        caminho = nil
        allow(rasterizacao).to receive(:pagina) do |pdf, *|
          caminho = pdf
          raise NoMethodError, 'bug'
        end
        allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

        expect { processor.extract }.to raise_error(NoMethodError)
        expect(caminho).to end_with('.pdf')
        expect(File).not_to exist(caminho)
      end

      # P1 — a Lia, mesmo na Fase 2, lê todas as páginas de texto, como na main.
      it 'lets the Lia read every page of text in the Fase 2' do
        stub_const("#{described_class}::MAX_PAGINAS_TEXTO", 1)
        stub_pages(['Primeira pagina com bastante texto', 'Segunda pagina com bastante texto'])
        lia = material(agent: instance_double(Autonomia::Agents::Agent, instrucao_mantida?: true))

        expect(described_class.new(lia).extract).to include('Segunda')
        expect(lia).not_to have_received(:paginas_de_fora=)
      end

      it 'does not run the OCR when the caller turned it off (attendance)' do
        stub_pages([' '])
        stub_ocr('nunca')

        expect(described_class.new(source, ocr: false).extract).to eq(" \n")
        expect(rasterizacao).not_to have_received(:pagina)
      end

      # O que ficou de fora vai para o metadata no mark_ready! (o PR 2 avisa o dono) e some quando nada fica de fora.
      context 'with a material of the base' do
        let(:agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support') }
        let(:source) do
          material = agente.sources.new(account: account, source_type: 'pdf', reference: 'manual.pdf')
          material.file.attach(io: StringIO.new('pdf-bytes'), filename: 'manual.pdf', content_type: 'application/pdf')
          material.save!
          material
        end

        def ler_e_terminar(fonte)
          token = fonte.begin_ingestion!
          described_class.new(fonte).extract
          fonte.mark_ready!(token, chunk_count: 1)
        end

        # Q1 — outra leitura venceu no meio do OCR: para antes da próxima página, sem gravar nada e sem ir ao Sentry.
        it 'stops before the next page when another reading wins, writing nothing' do
          stub_pages([' ', ' '])
          allow(rasterizacao).to receive(:pagina) do |_pdf, indice, **, &bloco|
            Autonomia::Agents::Source.find(source.id).begin_ingestion! if indice.zero?
            bloco.call("/tmp/pagina-#{indice}.png")
          end
          allow(ocr).to receive(:ler).and_return('TEXTO RECONHECIDO VIA OCR DO SCAN')
          allow(ChatwootExceptionTracker).to receive(:new)
          token = source.begin_ingestion!

          expect { described_class.new(source).extract }.to raise_error(Autonomia::Agents::Knowledge::Ingestor::Superseded)
          expect(rasterizacao).to have_received(:pagina).once
          expect(ChatwootExceptionTracker).not_to have_received(:new)
          expect(source.mark_ready!(token, chunk_count: 1)).to be(false)
          expect(source.reload.metadata).not_to have_key('paginas_de_fora')
        end

        it 'records the pages left out in the metadata, and clears it when none is left out' do
          stub_const("#{pdf_ocr}::MAX_PAGINAS_OCR", 1)
          stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN')
          stub_pages([' ', ' '])

          ler_e_terminar(source)
          expect(source.reload.metadata['paginas_de_fora']).to include('ocr_teto' => 1, 'ocr_alem_do_teto' => 1)

          stub_pages([' '])
          ler_e_terminar(Autonomia::Agents::Source.find(source.id))
          expect(source.reload.metadata).not_to have_key('paginas_de_fora')
        end
      end

      # V4 — o ImageMagick (um falso no PATH, que grava o que recebeu) só vê o temporário do próprio código, com o leitor
      # de PDF forçado; nada do nome que o cliente deu ao arquivo. O temporário some no fim.
      context 'with the real rasterization and a fake ImageMagick' do
        let(:pasta) { Dir.mktmpdir }
        let(:file) { double('attachment', attached?: true, download: pdf_em_memoria([a4])) } # rubocop:disable RSpec/VerifiedDoubles
        let(:source) { material(reference: '$(touch pwned);evil.pdf') }

        after { FileUtils.remove_entry(pasta) }

        it 'passes only its own temporary PDF to ImageMagick' do
          File.write(File.join(pasta, 'magick'), "#!/bin/sh\nprintf '%s\\n' \"$@\" > #{pasta}/argv; for u; do :; done; printf png > \"$u\"\n")
          File.chmod(0o755, File.join(pasta, 'magick'))
          allow(ocr).to receive(:ler).and_return('TEXTO RECONHECIDO VIA OCR DO SCAN')

          expect(with_modified_env(PATH: "#{pasta}:/usr/bin:/bin") { processor.extract }).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')

          argv = File.readlines(File.join(pasta, 'argv'), chomp: true)
          entrada = argv.find { |argumento| argumento.start_with?('pdf:') }
          expect(entrada).to start_with("pdf:#{Dir.tmpdir}").and end_with('.pdf[0]')
          expect(argv.join).not_to include('pwned', 'evil')
          expect(File).not_to exist(entrada.delete_prefix('pdf:').delete_suffix('[0]'))
        end
      end

      # V4 — PDFs de verdade, montados em memória, pelo leitor real (pdf-reader).
      describe 'PDFs built in memory' do
        before { stub_ocr('TEXTO RECONHECIDO VIA OCR DO SCAN') }

        def ler(bytes)
          allow(file).to receive(:download).and_return(bytes)
          processor.extract
        end

        it 'never rasterizes a giant MediaBox' do
          ler(pdf_em_memoria(['/MediaBox [0 0 14400 14400]']))

          expect(rasterizacao).not_to have_received(:pagina)
          expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_grandes' => [1]))
        end

        it 'never rasterizes a giant MediaBox inherited from the parent' do
          ler(pdf_em_memoria([''], pai: '/MediaBox [0 0 14400 14400]'))

          expect(rasterizacao).not_to have_received(:pagina)
        end

        it 'counts the UserUnit in the size and never rasterizes a page that grows past the ceiling' do
          ler(pdf_em_memoria(["#{a4} /UserUnit 10"]))

          expect(rasterizacao).not_to have_received(:pagina)
        end

        # O teto medido do ImageMagick com os limites da Rasterizacao (24 MP): 980 × 1400 pt (23,8 MP) vai; 1050 × 1500 pt
        # (27,3 MP) falharia no ImageMagick, então nem vai.
        it 'rasterizes a page up to the measured ceiling and leaves a bigger one out' do
          ler(pdf_em_memoria(['/MediaBox [0 0 980 1400]', '/MediaBox [0 0 1050 1500]']))

          expect(rasterizacao).to have_received(:pagina).once
          expect(rasterizacao).to have_received(:pagina).with(anything, 0, any_args)
          expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_grandes' => [2]))
        end

        # Q2 — MediaBox e UserUnit por referência indireta, resolvidas pelo leitor; valor que não é número não vai.
        it 'resolves an indirect MediaBox and an indirect number inside it' do
          expect(ler(pdf_em_memoria(['/MediaBox 4 0 R'], extras: ['[0 0 595 842]']))).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
          expect(ler(pdf_em_memoria(['/MediaBox [0 0 4 0 R 842]'], extras: ['595']))).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
          expect(rasterizacao).to have_received(:pagina).twice
        end

        it 'resolves an indirect UserUnit and leaves out the page that grows past the ceiling' do
          ler(pdf_em_memoria(["#{a4} /UserUnit 4 0 R"], extras: ['10']))

          expect(rasterizacao).not_to have_received(:pagina)
          expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_grandes' => [1]))
        end

        it 'leaves out a page whose size is not a number, without going to the tracker' do
          allow(ChatwootExceptionTracker).to receive(:new)
          ['/MediaBox [0 0 (a) 842]', "#{a4} /UserUnit (x)", "#{a4} /UserUnit 4 0 R"].each do |pagina|
            ler(pdf_em_memoria([pagina], extras: ['(x)']))
          end
          # A MediaBox indireta que não é lista o próprio leitor recusa: o material falha como PDF ruim.
          expect { ler(pdf_em_memoria(['/MediaBox 4 0 R'], extras: ['(x)'])) }
            .to raise_error(described_class::ExtractionError, /pdf_parse_failed/)

          expect(rasterizacao).not_to have_received(:pagina)
          expect(ChatwootExceptionTracker).not_to have_received(:new)
          expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_grandes' => [1])).thrice
        end

        it 'rasterizes a rotated A4 page, the rotation does not change the size' do
          expect(ler(pdf_em_memoria(["#{a4} /Rotate 90"]))).to eq('TEXTO RECONHECIDO VIA OCR DO SCAN')
          expect(rasterizacao).to have_received(:pagina).once
        end

        it 'reads 30 of 31 pages and leaves the last one out' do
          ler(pdf_em_memoria([a4] * 31))

          expect(rasterizacao).to have_received(:pagina).exactly(30).times
          expect(rasterizacao).not_to have_received(:pagina).with(anything, 30, any_args)
          expect(source).to have_received(:paginas_de_fora=).with(hash_including('ocr_alem_do_teto' => 1))
        end
      end

      # V4 — um PostScript com %PDF- depois do byte 0 nunca chega ao ImageMagick (o ghostscript o interpretaria).
      context 'with a PostScript that has %PDF- after byte 0' do
        let(:file) { double('attachment', attached?: true, download: pdf_em_memoria([a4], antes: "%!PS-Adobe-3.0\n")) } # rubocop:disable RSpec/VerifiedDoubles

        # O pdf-reader aceita o arquivo (procura o cabeçalho adiante); quem recusa é a Rasterizacao, antes do ImageMagick.
        it 'never rasterizes it' do
          allow(Process).to receive(:spawn)
          allow(ocr).to receive(:ler)
          allow(Rails.logger).to receive(:warn)

          expect(processor.extract.strip).to eq('')
          expect(Rails.logger).to have_received(:warn).with(/pdf_ocr_unavailable: .*nao_e_pdf/)

          expect(Process).not_to have_received(:spawn)
          expect(ocr).not_to have_received(:ler)
        end
      end
    end

    it 'raises ExtractionError on a malformed PDF' do
      allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError.new('boom'))

      expect { processor.extract }.to raise_error(described_class::ExtractionError, /pdf_parse_failed/)
    end
  end
end
