# #1426 — confere uma foto antes de ela virar material da base, sempre pelos BYTES, nunca pelo tipo que o cliente
# declarou (um texto declarado como image/png chegaria ao tesseract, que trata texto como lista de arquivos).
#
# - Tipo: o que o Construtor aceita (Config::IMAGE_CONTENT_TYPES), detectado pelo conteúdo (Marcel, sem nome nem tipo
#   declarado), como o BuilderImagesController.
# - Tamanho: até Config::MAX_IMAGE_BYTES (5 MB), o mesmo teto da foto da conversa.
# - Pixels: até MAX_PIXELS, lidos do cabeçalho (sem decodificar a imagem). 40 MP cobre foto de celular (12 a 24 MP, e
#   48 MP só no modo de alta resolução, que raramente cabe em 5 MB) e página escaneada (A4 a 300 DPI tem 8,7 MP); acima
#   disso é bomba de pixels: um PNG de 5 MB pode declarar 14.000 × 14.000 e pedir gigabytes ao OCR.
#
# Usado na porta (SourcesController), na foto da criação (FotosDaCriacao) e de novo no processador, logo antes do OCR.
module Autonomia::Agents::Knowledge::FotoConferida
  MAX_PIXELS = 40_000_000

  module_function

  # nil quando a foto passa; senão o motivo: :tipo, :tamanho ou :pixels.
  def problema(bytes)
    bytes = bytes.to_s.b
    return :tamanho if bytes.bytesize > Autonomia::Agents::Config::MAX_IMAGE_BYTES

    tipo = Marcel::MimeType.for(StringIO.new(bytes))
    return :tipo unless Autonomia::Agents::Config::IMAGE_CONTENT_TYPES.include?(tipo)

    largura, altura = Autonomia::Agents::Knowledge::DimensoesDaImagem.ler(bytes, tipo)
    return :pixels if largura.nil? || altura.nil? || largura * altura > MAX_PIXELS

    nil
  end
end
