# #1426 (#2425) — usado por Processors::PdfTrechos.
# O leitor de texto do pdf-reader, guardando a fonte (BaseFont) de cada caractere, que o TextRun não traz. A fonte só
# muda entre um texto mostrado e outro (operador Tf), então ela é marcada depois de cada Tj/TJ. Depende do interno do
# pdf-reader 2.16 (@characters, @state); se ele mudar, a fonte vira nil e só o tamanho da letra separa (o spec do título
# em outra fonte falha e avisa).
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
    fonte = sem_subconjunto(@state.current_font&.basefont)
    @characters.drop(antes).each { |caractere| fontes[caractere] = fonte }
  end

  # "ABCDEF+Arial" é um subconjunto da Arial embutido; outra parte do PDF pode embutir a mesma fonte como "GHIJKL+Arial".
  def sem_subconjunto(nome)
    prefixo, resto = nome.to_s.split('+', 2)
    resto && prefixo.size == 6 && prefixo == prefixo.upcase ? resto : nome&.to_s
  end
end
