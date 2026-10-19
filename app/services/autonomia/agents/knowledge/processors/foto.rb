# #1426 (tema 4) — a foto mandada na criação, como material da base: o texto dela sai pelo mesmo OCR do PDF escaneado
# (Processors::Ocr). Sem texto legível volta vazio, e a ingestão marca o material como não lido.
#
# Antes do OCR, os bytes são conferidos de novo (FotoConferida: tipo pelo conteúdo, tamanho e pixels): o tesseract nunca
# recebe o que não for imagem. Sem o OCR na máquina ou com o tempo estourado, falha com `foto_ocr_unavailable`.
class Autonomia::Agents::Knowledge::Processors::Foto < Autonomia::Agents::Knowledge::Processors::Base
  OCR = Autonomia::Agents::Knowledge::Processors::Ocr

  def extract
    bytes = download_bytes
    problema = Autonomia::Agents::Knowledge::FotoConferida.problema(bytes)
    raise ExtractionError, "foto_invalida: #{problema}" if problema

    texto = with_tempfile { |caminho| OCR.ler(caminho) }
    texto.force_encoding('UTF-8').scrub('').strip
  rescue OCR::Indisponivel
    raise UnsupportedFormat, 'foto_ocr_unavailable'
  rescue OCR::Falhou
    raise ExtractionError, 'foto_ocr_failed'
  end
end
