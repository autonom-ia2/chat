# O OCR da base (tesseract, pt-BR), num lugar só: o PDF escaneado lê cada página rasterizada por aqui, e a foto da criação
# (#1426) lê a própria imagem. Quem chama cuida de quando o OCR não está disponível (LoadError).
module Autonomia::Agents::Knowledge::Processors::Ocr
  IDIOMA = 'por'.freeze

  module_function

  def ler(caminho)
    require 'rtesseract'
    RTesseract.new(caminho, lang: IDIOMA).to_s.to_s
  end
end
