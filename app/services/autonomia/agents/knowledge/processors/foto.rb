# #1426 (tema 4) — a foto mandada na criação, como material da base: o texto dela sai pelo mesmo OCR do PDF escaneado
# (Processors::Ocr). Sem texto legível volta vazio, e a ingestão marca o material como não lido. Sem o OCR na máquina,
# falha com motivo claro em vez de virar um material vazio.
class Autonomia::Agents::Knowledge::Processors::Foto < Autonomia::Agents::Knowledge::Processors::Base
  def extract
    texto = with_tempfile { |caminho| Autonomia::Agents::Knowledge::Processors::Ocr.ler(caminho) }
    texto.force_encoding('UTF-8').scrub('').strip
  rescue LoadError
    raise UnsupportedFormat, 'foto_ocr_unavailable'
  end
end
