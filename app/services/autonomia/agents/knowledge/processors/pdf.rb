module Autonomia
  module Agents
    module Knowledge
      module Processors
        # pdf: extração de texto via gem `pdf-reader` (PDF::Reader). A gem é opcional neste fork —
        # se ausente, degrada p/ UnsupportedFormat (a fonte vira `failed` com mensagem clara) em vez
        # de quebrar o boot. Concatena o texto de cada página. Quando o PDF é escaneado (sem camada
        # de texto), a extração normal volta vazia; nesse caso cai p/ OCR (PdfOcr: Rasterizacao + Ocr).
        class Pdf < Base
          include PdfOcr
          include PdfParagrafos

          # Abaixo deste tamanho (após strip) a extração é "quase vazia" (PDF escaneado / só imagem):
          # vale tentar OCR em vez de marcar a fonte como falha por texto ausente.
          OCR_MIN_CHARS = 20
          # #1426 (revisão adversarial) — na Fase 2, teto de páginas da extração de TEXTO. Ler a camada de texto é barato
          # (milissegundos por página), mas sem teto um PDF de milhares de páginas vira uma base enorme de um material só.
          # 300 páginas cobrem manual, catálogo e tabela completos; o que passar fica de fora e o dono é avisado. Fora
          # da Fase 2 e na Lia (agente protegido), sem teto, como antes.
          MAX_PAGINAS_TEXTO = 300
          # #1426 (t4e) — material grande: acima disto, na Fase 2 e fora da Lia, o texto também sai em seções de
          # PAGINAS_POR_SECAO páginas (Source#secoes), para cada trecho saber de que páginas veio e o resumo cobrir o
          # material inteiro, não só o começo. O material pequeno fica como antes.
          PAGINAS_DE_MATERIAL_GRANDE = 50
          PAGINAS_POR_SECAO = 25

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
            @paginas_de_fora = {}
            texto = with_tempfile do |path|
              todas = PDF::Reader.new(path).pages
              @paginas_total = todas.size
              paginas = paginas_do_texto(todas)
              textos = textos_das_paginas(paginas)
              text = textos.join
              next ocr_fallback(text, path, paginas) if @ocr && text.strip.length < OCR_MIN_CHARS

              registrar_secoes(textos)
              text
            end
            registrar_paginas_de_fora
            texto
          rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
            raise ExtractionError, "pdf_parse_failed: #{e.message}"
          end

          private

          # #1426 — na Fase 2, fora da Lia, cada página sai em parágrafos pela posição das linhas (PdfParagrafos); fora
          # disso, o `page.text` da main.
          def textos_das_paginas(paginas)
            textos = fase2_na_conta? && !agente_protegido? ? textos_em_paragrafos(paginas) : paginas.map { |page| "#{page.text}\n" }
            textos.map { |texto| texto.force_encoding('UTF-8').scrub('') }
          end

          def fase2_na_conta?
            @source.respond_to?(:account) && Autonomia::Agents::Fase2.ligada?(@source.account)
          end

          # A Lia (instrução mantida pela Autonom.ia) fica como na main, também na Fase 2.
          def agente_protegido?
            @source.respond_to?(:agent) && @source.agent&.instrucao_mantida? == true
          end

          def paginas_do_texto(pages)
            return pages unless fase2_na_conta? && !agente_protegido? && pages.size > MAX_PAGINAS_TEXTO

            alem = pages.size - MAX_PAGINAS_TEXTO
            @paginas_de_fora = @paginas_de_fora.merge('texto_teto' => MAX_PAGINAS_TEXTO, 'texto_alem_do_teto' => alem)
            pages.first(MAX_PAGINAS_TEXTO)
          end

          # As seções do material grande, pelo texto de cada página lida (em ordem, a partir da 1ª).
          def registrar_secoes(textos)
            return unless textos.size > PAGINAS_DE_MATERIAL_GRANDE && fase2_na_conta? && !agente_protegido?
            return unless @source.respond_to?(:secoes=)

            @source.secoes = textos.each_slice(PAGINAS_POR_SECAO).with_index.map do |grupo, indice|
              inicio = (indice * PAGINAS_POR_SECAO) + 1
              { 'paginas' => [inicio, inicio + grupo.size - 1], 'texto' => grupo.join }
            end
          end

          # O que ficou de fora desta leitura vai para o log e para o material (Source#paginas_de_fora, gravado pelo
          # mark_ready! sob a guarda de token), para o aviso ao dono.
          def registrar_paginas_de_fora
            return if @paginas_de_fora.empty?

            # #1426 (4b) — o total de páginas do arquivo, para o aviso dizer "li X das N". Só na Fase 2, fora da Lia: fora
            # dela, o registro é o da main.
            @paginas_de_fora = @paginas_de_fora.merge('paginas_total' => @paginas_total) if paginas_total?
            Rails.logger.warn("[autonomia] pdf_paginas_de_fora #{@paginas_de_fora.to_json}")
            @source.paginas_de_fora = @paginas_de_fora if @source.respond_to?(:paginas_de_fora=)
          end

          def paginas_total?
            @paginas_total.present? && fase2_na_conta? && !agente_protegido?
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
