# Vídeo curto de trajeto de um artigo da Central de Ajuda: `<id>.mp4`, com a legenda em `<id>.vtt` e o
# pôster em `<id>.jpg`, todos em public/central-de-ajuda/videos. Artigo sem `.mp4` não tem vídeo.
# Usado pela publicação dos artigos e pela tela Primeiros passos, que mostra o mesmo vídeo.
class Autonomia::CentralDeAjuda::VideoDoArtigo
  PASTA = Rails.public_path.join('central-de-ajuda/videos')
  URL = '/central-de-ajuda/videos/'.freeze

  def self.para(id, pasta: PASTA)
    return unless File.exist?(pasta.join("#{id}.mp4"))

    { 'arquivo' => "#{URL}#{id}.mp4", 'legenda' => arquivo(id, 'vtt', pasta), 'poster' => arquivo(id, 'jpg', pasta) }
  end

  def self.arquivo(id, extensao, pasta)
    "#{URL}#{id}.#{extensao}" if File.exist?(pasta.join("#{id}.#{extensao}"))
  end
  private_class_method :arquivo
end
