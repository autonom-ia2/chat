module Autonomia
  module Agents
    module Knowledge
      module Processors
        # pdf: extração de texto via gem `pdf-reader` (PDF::Reader). A gem é opcional neste fork —
        # se ausente, degrada p/ UnsupportedFormat (a fonte vira `failed` com mensagem clara) em vez
        # de quebrar o boot. Concatena o texto de cada página. Quando o PDF é escaneado (sem camada
        # de texto), a extração normal volta vazia; nesse caso cai p/ OCR (Processors::Rasterizacao + Processors::Ocr).
        class Pdf < Base
          # Abaixo deste tamanho (após strip) a extração é "quase vazia" (PDF escaneado / só imagem):
          # vale tentar OCR em vez de marcar a fonte como falha por texto ausente.
          OCR_MIN_CHARS = 20
          # Pixels por ponto da página no OCR: o PDF mede em pontos (72 por polegada) e a página é lida a 300 DPI.
          DPI_POR_PONTO = Rasterizacao::DPI / 72.0
          # Teto de páginas no OCR do PDF escaneado. Medido em 19/10 na base da imagem (Alpine 3.21, ImageMagick 7.1.1,
          # tesseract 5.5): uma página A4 leva ~0,8 s para rasterizar a 300 DPI e 0,4 a 0,8 s de OCR, então 30 páginas
          # são ~1 min de job, com folga para página densa e máquina carregada (e cada uma tem o seu tempo máximo).
          # 30 cobre cardápio, tabela de preços e manual curto, o material de um pequeno negócio; um escaneado maior
          # quase sempre é arquivo inteiro. O resto fica de fora e vai para o metadata, para o dono ser avisado.
          MAX_PAGINAS_OCR = 30

          # OCR é OPCIONAL porque o custo dele não tem teto: rasteriza página por página a 300 DPI e
          # passa cada uma pelo tesseract. Num PDF escaneado de poucos MB isso são dezenas de páginas
          # e centenas de segundos.
          #
          # Na INGESTÃO da base de conhecimento vale (default `true`): roda em job, ninguém espera, e
          # um manual escaneado sem OCR não vira conhecimento nenhum.
          #
          # No ATENDIMENTO não vale: o cliente está do outro lado e o turno tem teto de 120s. Lá o
          # chamador passa `ocr: false`, e um PDF sem camada de texto simplesmente não é lido — o
          # agente pede os dados, que é o comportamento que já existia antes de haver leitura de PDF.
          def initialize(source, ocr: true)
            super(source)
            @ocr = ocr
          end

          def extract
            ensure_gem!
            with_tempfile do |path|
              reader = PDF::Reader.new(path)
              text = reader.pages.map { |page| "#{page.text}\n" }.join.force_encoding('UTF-8').scrub('')
              next text unless @ocr && text.strip.length < OCR_MIN_CHARS

              ocr_fallback(text, path, reader.pages)
            end
          rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
            raise ExtractionError, "pdf_parse_failed: #{e.message}"
          end

          private

          # PDF escaneado: rasteriza cada página (Processors::Rasterizacao: ImageMagick com limite de recurso e tempo
          # máximo) e passa por OCR (Processors::Ocr -> binário tesseract, idioma pt-BR, com tempo máximo). Guardado: se
          # um binário faltar em runtime, loga aviso e devolve o texto original (vazio) — nunca levanta erro novo que
          # quebre a ingestão. Deps de sistema instaladas na imagem prod (docker/Dockerfile: imagemagick ghostscript
          # tesseract-ocr tesseract-ocr-data-por poppler-utils).
          #
          # #1426 (revisão adversarial) — antes, cada página era aberta pelo nome "arquivo.pdf[N]", que não existe em
          # disco: o OCR do PDF escaneado falhava sempre, em silêncio (só o aviso no log). Agora funciona, e por isso só
          # roda na Fase 2 (piloto); fora dela o resultado é o de antes: o texto original e o aviso no log.
          def ocr_fallback(text, path, pages)
            unless ocr_na_conta?
              Rails.logger.warn('[autonomia] pdf_ocr_unavailable: fora_da_fase2')
              return text
            end

            ocr = ocr_pages(path, pages).force_encoding('UTF-8').scrub('').strip
            ocr.length >= OCR_MIN_CHARS ? ocr : text
          rescue StandardError => e
            Rails.logger.warn("[autonomia] pdf_ocr_unavailable: #{e.class}: #{e.message}")
            text
          end

          def ocr_na_conta?
            @source.respond_to?(:account) && Autonomia::Agents::Fase2.ligada?(@source.account)
          end

          # Uma imagem por página (300 DPI p/ OCR legível), OCR em cada uma, com quebra de linha entre páginas. Ficam de
          # fora as páginas depois de MAX_PAGINAS_OCR e a que a 300 DPI passaria do teto de pixels da foto (MediaBox
          # grande: A1 ou maior), sem rasterizar; o que ficou de fora vai para o log e o metadata do material.
          def ocr_pages(pdf_path, pages)
            cabem, grandes = pages.first(MAX_PAGINAS_OCR).each_with_index.partition { |page, _| pagina_cabe?(page) }
            registrar_paginas_de_fora(total: pages.size, grandes: grandes.map { |_, index| index + 1 })
            cabem.map { |_, index| Rasterizacao.pagina(pdf_path, index) { |png| Ocr.ler(png) } }.join("\n")
          end

          def pagina_cabe?(page)
            pixels = (page.width.abs * DPI_POR_PONTO) * (page.height.abs * DPI_POR_PONTO)
            pixels <= Autonomia::Agents::Knowledge::FotoConferida::MAX_PIXELS
          end

          # `ocr_paginas_de_fora` no metadata: { teto, alem_do_teto (quantas), grandes (números das páginas) }. Some
          # quando nada ficou de fora. É o que o PR 2 usa para avisar o dono.
          def registrar_paginas_de_fora(total:, grandes:)
            alem = [total - MAX_PAGINAS_OCR, 0].max
            de_fora = { 'teto' => MAX_PAGINAS_OCR, 'alem_do_teto' => alem, 'grandes' => grandes } if alem.positive? || grandes.any?
            Rails.logger.warn("[autonomia] pdf_ocr_paginas_de_fora alem_do_teto=#{alem} grandes=#{grandes.join(',')}") if de_fora
            @source.marcar_paginas_fora_do_ocr!(de_fora) if @source.respond_to?(:marcar_paginas_fora_do_ocr!)
          end

          def ensure_gem!
            require 'pdf-reader'
          rescue LoadError
            raise UnsupportedFormat, 'pdf_support_unavailable'
          end
        end
      end
    end
  end
end
