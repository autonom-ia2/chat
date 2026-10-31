# #1426 (#2425) — usado por Processors::PdfTrechos.
# O leitor de texto do pdf-reader, guardando a fonte (BaseFont) de cada caractere, que o TextRun não traz. A fonte só
# muda entre um texto mostrado e outro (operador Tf), então ela é marcada depois de cada Tj/TJ.
class Autonomia::Agents::Knowledge::Processors::PdfTrechos::Leitor < PDF::Reader::PageTextReceiver
  def fontes
    @fontes ||= {}.compare_by_identity
  end

  def show_text(string)
    marcar { super }
  end

  def show_text_with_positioning(params)
    marcar { super }
  end

  private

  def marcar
    antes = @characters.size
    yield
    fonte = @state.current_font&.basefont
    @characters.drop(antes).each { |caractere| fontes[caractere] = fonte }
  end
end
