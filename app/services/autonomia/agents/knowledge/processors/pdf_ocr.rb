# O OCR do PDF escaneado (incluído em Processors::Pdf): cada página vira PNG (Rasterizacao: ImageMagick com limite de
# recurso e tempo máximo) e passa pelo tesseract (Ocr, também com tempo máximo). Deps de sistema na imagem prod
# (docker/Dockerfile: imagemagick ghostscript tesseract-ocr tesseract-ocr-data-por poppler-utils).
#
# #1426 (revisão adversarial) — antes, cada página era aberta pelo nome "arquivo.pdf[N]", que não existe em disco: o OCR
# do PDF escaneado falhava sempre, em silêncio. Agora funciona, e por isso só roda na Fase 2 (piloto) e nunca na Lia;
# fora disso o resultado é o de antes: o texto original e o aviso no log.
#
# Ficam de fora, e vão para o aviso ao dono (`ocr_*` em paginas_de_fora): as páginas depois de MAX_PAGINAS_OCR, a que a
# 300 DPI passaria do teto de pixels (MediaBox × UserUnit), e as que não couberam no prazo total.
module Autonomia::Agents::Knowledge::Processors::PdfOcr
  # Pixels por ponto da página no OCR: o PDF mede em pontos (72 por polegada) e a página é lida a 300 DPI.
  DPI_POR_PONTO = Autonomia::Agents::Knowledge::Processors::Rasterizacao::DPI / 72.0
  # Teto de páginas no OCR. Medido em 19/10 na base da imagem (Alpine 3.21, ImageMagick 7.1.1, tesseract 5.5): uma
  # página A4 leva ~0,8 s para rasterizar a 300 DPI e 0,4 a 0,8 s de OCR, então 30 páginas são ~1 min de job. 30 cobre
  # cardápio, tabela de preços e manual curto, o material de um pequeno negócio; um escaneado maior quase sempre é
  # arquivo inteiro.
  MAX_PAGINAS_OCR = 30
  # Prazo total do OCR de um PDF: 5 min, cinco vezes o esperado para 30 páginas. Cada página ainda tem o seu tempo
  # máximo (Rasterizacao e Ocr); o prazo segura a soma, para o job não ficar preso numa sequência de páginas lentas.
  PRAZO_OCR = 300
  # Teto de pixels de uma página a 300 DPI. Menor que o da foto (40 MP) porque o ImageMagick, com os limites da
  # Rasterizacao, não comporta mais: medido em 19/10 na imagem (Alpine 3.21, ImageMagick 7.1.1-41 Q16-HDRI), 24,3 MP
  # (1000 × 1400 pt) rasteriza e 27,3 MP (1050 × 1500 pt) falha por falta de cache. A3 tem 17,4 MP; A2 (34,8 MP) fica de
  # fora. Sem este teto, uma página que passasse da conta derrubava o OCR do PDF inteiro.
  MAX_PIXELS_PAGINA = 24_000_000

  # O relógio do prazo (monotônico), à parte para o spec controlar o tempo.
  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  private

  def ocr_na_conta?
    fase2_na_conta? && !(@source.respond_to?(:agent) && @source.agent&.instrucao_mantida?)
  end

  # Só as falhas esperadas (binário ausente ou que recusou, tempo estourado, PDF que o leitor não entende) voltam ao
  # texto original com aviso no log. Qualquer outra vai ao Sentry e sobe: é bug, não PDF ruim.
  def ocr_fallback(text, path, pages)
    unless ocr_na_conta?
      Rails.logger.warn('[autonomia] pdf_ocr_unavailable: fora_da_fase2')
      return text
    end

    ocr = ocr_pages(path, pages).force_encoding('UTF-8').scrub('').strip
    ocr.length >= Autonomia::Agents::Knowledge::Processors::Pdf::OCR_MIN_CHARS ? ocr : text
  rescue StandardError => e
    raise_inesperada!(e) unless falha_esperada?(e)
    Rails.logger.warn("[autonomia] pdf_ocr_unavailable: #{e.class}: #{e.message}")
    text
  end

  def falha_esperada?(erro)
    processadores = Autonomia::Agents::Knowledge::Processors
    [processadores::Rasterizacao::Falhou, processadores::Ocr::Indisponivel, processadores::Ocr::Falhou,
     PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError].any? { |classe| erro.is_a?(classe) }
  end

  def raise_inesperada!(erro)
    ChatwootExceptionTracker.new(erro, account: @source.account).capture_exception
    raise erro
  end

  def ocr_pages(pdf_path, pages)
    candidatas = pages.first(MAX_PAGINAS_OCR).each_with_index.to_a
    cabem, grandes = candidatas.partition { |page, _| pagina_cabe?(page) }
    lidas, prazo = ler_no_prazo(pdf_path, cabem)
    anotar_ocr(alem: pages.size - candidatas.size, grandes: numeros(grandes), prazo: prazo)
    lidas.join("\n")
  end

  # Lê as páginas em ordem enquanto houver prazo; as que sobrarem voltam pelos números.
  def ler_no_prazo(pdf_path, paginas)
    relogio = Autonomia::Agents::Knowledge::Processors::PdfOcr
    limite = relogio.agora + PRAZO_OCR
    lidas = []
    paginas.each_with_index do |(_, index), posicao|
      return [lidas, numeros(paginas.drop(posicao))] if relogio.agora > limite

      lidas << Autonomia::Agents::Knowledge::Processors::Rasterizacao.pagina(pdf_path, index) do |png|
        Autonomia::Agents::Knowledge::Processors::Ocr.ler(png)
      end
    end
    [lidas, []]
  end

  def numeros(paginas)
    paginas.map { |_, index| index + 1 }
  end

  # /UserUnit (PDF 1.6) multiplica o tamanho de cada unidade da página; sem ela, 1.
  def pagina_cabe?(page)
    unidade = page.attributes[:UserUnit].is_a?(Numeric) ? page.attributes[:UserUnit].to_f : 1.0
    pixels = (page.width.abs * unidade * DPI_POR_PONTO) * (page.height.abs * unidade * DPI_POR_PONTO)
    pixels <= MAX_PIXELS_PAGINA
  end

  def anotar_ocr(alem:, grandes:, prazo:)
    return if alem.zero? && grandes.empty? && prazo.empty?

    @paginas_de_fora = @paginas_de_fora.merge(
      'ocr_teto' => MAX_PAGINAS_OCR, 'ocr_alem_do_teto' => alem, 'ocr_grandes' => grandes, 'ocr_prazo' => prazo
    )
  end
end
