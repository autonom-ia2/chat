# Vídeo curto de trajeto de um artigo da Central de Ajuda: `<id>.mp4`, com a legenda em `<id>.vtt` e o
# pôster em `<id>.jpg`, todos em public/central-de-ajuda/videos. Artigo sem `.mp4` não tem vídeo.
# Usado pela publicação dos artigos e pela tela Primeiros passos, que mostra o mesmo vídeo.
#
# O servidor entrega o que está em public/ com cache de um ano. Um vídeo regravado mantém o nome do
# arquivo, então o endereço leva a versão do conteúdo (`?v=`): conteúdo novo, endereço novo, e o
# navegador baixa de novo em vez de mostrar o vídeo antigo que já tinha guardado.
class Autonomia::CentralDeAjuda::VideoDoArtigo
  PASTA = Rails.public_path.join('central-de-ajuda/videos')
  URL = '/central-de-ajuda/videos/'.freeze
  TAMANHO_DA_VERSAO = 12

  def self.para(id, pasta: PASTA)
    return unless File.exist?(pasta.join("#{id}.mp4"))

    { 'arquivo' => arquivo(id, 'mp4', pasta), 'legenda' => arquivo(id, 'vtt', pasta), 'poster' => arquivo(id, 'jpg', pasta) }
  end

  def self.arquivo(id, extensao, pasta)
    caminho = pasta.join("#{id}.#{extensao}")
    "#{URL}#{id}.#{extensao}?v=#{versao(caminho)}" if File.exist?(caminho)
  end

  # Ler o vídeo inteiro a cada pedido da tela sairia caro: a versão fica guardada enquanto o arquivo
  # não muda (mesmo caminho, mesma data de modificação).
  def self.versao(caminho)
    chave = [caminho.to_s, File.mtime(caminho).to_r]
    versoes[chave] ||= Digest::SHA256.file(caminho).hexdigest[0, TAMANHO_DA_VERSAO]
  end

  def self.versoes
    @versoes ||= {}
  end
  private_class_method :arquivo, :versao, :versoes
end
