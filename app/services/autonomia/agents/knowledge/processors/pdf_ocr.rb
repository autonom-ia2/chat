# O OCR do PDF escaneado (incluído em Processors::Pdf): cada página vira PNG (Rasterizacao: ImageMagick com limite de
# recurso e tempo máximo) e passa pelo tesseract (Ocr, também com tempo máximo). Deps de sistema na imagem prod
# (docker/Dockerfile: imagemagick ghostscript tesseract-ocr tesseract-ocr-data-por poppler-utils).
#
# #1426 (revisão adversarial) — antes, cada página era aberta pelo nome "arquivo.pdf[N]", que não existe em disco: o OCR
# do PDF escaneado falhava sempre, em silêncio. Agora funciona, e por isso só roda na Fase 2 (piloto) e nunca na Lia;
# fora disso o resultado é o de antes: o texto original e o aviso no log (`fora_da_fase2` ou `agente_protegido`).
#
# Ficam de fora, e vão para o aviso ao dono (`ocr_*` em paginas_de_fora): as páginas depois de MAX_PAGINAS_OCR, a que a
# 300 DPI passaria do teto de pixels ou não tem tamanho legível (`ocr_grandes`), as que não couberam no prazo total
# (`ocr_prazo`) e as que o ImageMagick ou o tesseract recusaram (`ocr_falhou`). Antes de cada página, confere que esta
# leitura ainda é a vigente: se outra venceu, para sem gravar nada (Ingestor::Superseded, o no-op do ProcessJob).
module Autonomia::Agents::Knowledge::Processors::PdfOcr
  # Pixels por ponto da página no OCR: o PDF mede em pontos (72 por polegada) e a página é lida a 300 DPI.
  DPI_POR_PONTO = Autonomia::Agents::Knowledge::Processors::Rasterizacao::DPI / 72.0
  # Teto de páginas no OCR. Medido em 19/10 na base da imagem (Alpine 3.21, ImageMagick 7.1.1, tesseract 5.5): uma
  # página A4 leva ~0,8 s para rasterizar a 300 DPI e 0,4 a 0,8 s de OCR, então 30 páginas são ~1 min de job. 30 cobre
  # cardápio, tabela de preços e manual curto, o material de um pequeno negócio; um escaneado maior quase sempre é
  # arquivo inteiro.
  MAX_PAGINAS_OCR = 30
  # Prazo total do OCR de um PDF: 5 min, cinco vezes o esperado para 30 páginas. Cada página recebe o menor entre o seu
  # tempo máximo e o que resta do prazo, então a soma nunca passa dele.
  PRAZO_OCR = 300
  # Teto de pixels de uma página a 300 DPI. Menor que o da foto (40 MP) porque o ImageMagick, com os limites da
  # Rasterizacao, não comporta mais: medido em 19/10 na imagem (Alpine 3.21, ImageMagick 7.1.1-41 Q16-HDRI), 24,3 MP
  # (1000 × 1400 pt) rasteriza e 27,3 MP (1050 × 1500 pt) falha por falta de cache. A3 tem 17,4 MP; A2 (34,8 MP) fica de
  # fora.
  MAX_PIXELS_PAGINA = 24_000_000
  # Falhas de UMA página (o ImageMagick ou o tesseract a recusou, ou estourou o tempo): ela é pulada e as outras seguem.
  FALHAS_DA_PAGINA = [Autonomia::Agents::Knowledge::Processors::Rasterizacao::Falhou,
                      Autonomia::Agents::Knowledge::Processors::Ocr::Falhou].freeze

  # O relógio do prazo (monotônico), à parte para o spec controlar o tempo.
  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  private

  # Por que o OCR não roda neste material: fora do piloto, ou agente protegido (a Lia, de instrução mantida). nil = roda.
  def motivo_sem_ocr
    return 'fora_da_fase2' unless fase2_na_conta?

    'agente_protegido' if agente_protegido?
  end

  # Só as falhas esperadas (binário ausente ou que recusou, tempo estourado, PDF que o leitor não entende) voltam ao
  # texto original com aviso no log. Outra leitura que venceu sobe como está (no-op do job). Qualquer outra falha vai ao
  # Sentry e sobe: é bug, não PDF ruim.
  def ocr_fallback(text, path, pages)
    motivo = motivo_sem_ocr
    if motivo
      Rails.logger.warn("[autonomia] pdf_ocr_unavailable: #{motivo}")
      return text
    end

    ocr = ocr_pages(path, pages).force_encoding('UTF-8').scrub('').strip
    return text if ocr.length < Autonomia::Agents::Knowledge::Processors::Pdf::OCR_MIN_CHARS

    @source.leitura_de_imagem = true if @source.respond_to?(:leitura_de_imagem=)
    ocr
  rescue Autonomia::Agents::Knowledge::Ingestor::Superseded
    raise
  rescue StandardError => e
    raise_inesperada!(e) unless falha_esperada?(e)
    Rails.logger.warn("[autonomia] pdf_ocr_unavailable: #{e.class}: #{e.message}")
    text
  end

  def falha_esperada?(erro)
    [*FALHAS_DA_PAGINA, Autonomia::Agents::Knowledge::Processors::Ocr::Indisponivel,
     PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError].any? { |classe| erro.is_a?(classe) }
  end

  def raise_inesperada!(erro)
    ChatwootExceptionTracker.new(erro, account: @source.account).capture_exception
    raise erro
  end

  # Se todas as páginas tentadas falharem, o que ficou de fora é anotado e a última falha sobe: o resultado é o de
  # antes (texto original e o aviso), agora com o aviso ao dono.
  def ocr_pages(pdf_path, pages)
    candidatas = pages.first(MAX_PAGINAS_OCR).each_with_index.to_a
    cabem, grandes = candidatas.partition { |page, _| pagina_cabe?(page) }
    leitura = ler_no_prazo(pdf_path, cabem)
    anotar_ocr(alem: pages.size - candidatas.size, grandes: numeros(grandes), prazo: leitura[:prazo], falhou: leitura[:falhou])
    raise leitura[:erro] if leitura[:lidas].empty? && leitura[:erro]

    leitura[:lidas].join("\n")
  end

  # Lê as páginas em ordem enquanto houver prazo; as que sobrarem vão para `prazo`. #1427: antes de cada uma, anota no material
  # "página X de N" (N = as que vão ser lidas, até MAX_PAGINAS_OCR), que a linha do material mostra enquanto lê.
  def ler_no_prazo(pdf_path, paginas)
    limite = Autonomia::Agents::Knowledge::Processors::PdfOcr.agora + PRAZO_OCR
    leitura = { lidas: [], prazo: [], falhou: [], erro: nil }
    paginas.each_with_index do |(_, index), posicao|
      return leitura.merge(prazo: numeros(paginas.drop(posicao))) unless restante(limite).positive?

      conferir_leitura_vigente!
      anotar_progresso(posicao + 1, paginas.size)
      leitura = ler_pagina(pdf_path, index, limite, leitura)
    end
    leitura
  end

  # Uma página que o ImageMagick ou o tesseract recusa é pulada e anotada em `falhou` (em `prazo`, se o prazo acabou no
  # meio dela); as outras seguem. Sem o tesseract (Ocr::Indisponivel) nenhuma página vai funcionar: sobe e para tudo.
  def ler_pagina(pdf_path, index, limite, leitura)
    processadores = Autonomia::Agents::Knowledge::Processors
    tempo = [processadores::Rasterizacao::TEMPO_MAXIMO, restante(limite)].min
    texto = processadores::Rasterizacao.pagina(pdf_path, index, tempo: tempo) do |png|
      processadores::Ocr.ler(png, tempo: restante(limite).clamp(0.1, processadores::Ocr::TEMPO_MAXIMO))
    end
    leitura.merge(lidas: leitura[:lidas] + [texto])
  rescue *FALHAS_DA_PAGINA => e
    Rails.logger.warn("[autonomia] pdf_ocr_pagina_falhou pagina=#{index + 1} #{e.class}: #{e.message}")
    motivo = restante(limite).positive? ? :falhou : :prazo
    leitura.merge(motivo => leitura[motivo] + [index + 1]).merge(erro: e)
  end

  def restante(limite)
    limite - Autonomia::Agents::Knowledge::Processors::PdfOcr.agora
  end

  def conferir_leitura_vigente!
    return unless @source.respond_to?(:leitura_vigente?)
    raise Autonomia::Agents::Knowledge::Ingestor::Superseded, 'leitura_superada' unless @source.leitura_vigente?
  end

  def anotar_progresso(pagina, total)
    @source.anotar_progresso!(pagina: pagina, total: total) if @source.respond_to?(:anotar_progresso!)
  end

  def numeros(paginas)
    paginas.map { |_, index| index + 1 }
  end

  def pagina_cabe?(page)
    largura, altura = Autonomia::Agents::Knowledge::Processors::TamanhoDaPagina.em_pontos(page)
    return false if largura.nil?

    (largura * DPI_POR_PONTO) * (altura * DPI_POR_PONTO) <= MAX_PIXELS_PAGINA
  end

  def anotar_ocr(alem:, grandes:, prazo:, falhou:)
    return if alem.zero? && [grandes, prazo, falhou].all?(&:empty?)

    @paginas_de_fora = @paginas_de_fora.merge(
      'ocr_teto' => MAX_PAGINAS_OCR, 'ocr_alem_do_teto' => alem, 'ocr_grandes' => grandes, 'ocr_prazo' => prazo,
      'ocr_falhou' => falhou
    )
  end
end
