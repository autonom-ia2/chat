# #1426 (tema 4) — a foto mandada na criação, como material da base: o texto dela sai pelo mesmo OCR do PDF escaneado
# (Processors::Ocr). Sem texto legível volta vazio, e a ingestão marca o material como não lido.
#
# Antes do OCR, os bytes são conferidos de novo (FotoConferida: tipo pelo conteúdo, tamanho, animação e pixels): o
# tesseract nunca recebe o que não for imagem. Um download só: o arquivo temporário recebe os mesmos bytes conferidos,
# com a extensão do tipo detectado neles. Sem o OCR na máquina ou com o tempo estourado, falha com
# `foto_ocr_unavailable`.
class Autonomia::Agents::Knowledge::Processors::Foto < Autonomia::Agents::Knowledge::Processors::Base
  OCR = Autonomia::Agents::Knowledge::Processors::Ocr
  EXTENSOES = { 'image/png' => '.png', 'image/jpeg' => '.jpg', 'image/gif' => '.gif', 'image/webp' => '.webp' }.freeze

  def extract
    bytes = download_bytes.b
    problema = Autonomia::Agents::Knowledge::FotoConferida.problema(bytes)
    raise ExtractionError, "foto_invalida: #{problema}" if problema

    extensao = EXTENSOES.fetch(Marcel::MimeType.for(StringIO.new(bytes)))
    texto = with_tempfile(bytes: bytes, extensao: extensao) { |caminho| OCR.ler(caminho) }
    texto.force_encoding('UTF-8').scrub('').strip
  rescue OCR::Indisponivel
    raise UnsupportedFormat, 'foto_ocr_unavailable'
  rescue OCR::Falhou
    raise ExtractionError, 'foto_ocr_failed'
  end
end
