# Vídeo curto de trajeto de um artigo da Central de Ajuda: `<id>.mp4`, com a legenda em `<id>.vtt` e o
# pôster em `<id>.jpg`, todos em public/central-de-ajuda/videos. Artigo sem `.mp4` não tem vídeo.
# Usado pela publicação dos artigos e pela tela Primeiros passos, que mostra o mesmo vídeo.
#
# O servidor entrega o que está em public/ com cache de um ano. Um vídeo regravado mantém o nome do
# arquivo, então o endereço leva a versão do conteúdo (`?v=`): conteúdo novo, endereço novo, e o
# navegador baixa de novo em vez de mostrar o vídeo antigo que já tinha guardado.
#
# `duracao` (segundos) é o fim da última legenda: a lista de um assunto mostra quanto tempo cada vídeo
# leva sem abrir o .mp4 (#977). Sem legenda, ou com tempo ilegível, fica nil.
class Autonomia::CentralDeAjuda::VideoDoArtigo
  PASTA = Rails.public_path.join('central-de-ajuda/videos')
  URL = '/central-de-ajuda/videos/'.freeze
  TAMANHO_DA_VERSAO = 12
  BOM = "\xEF\xBB\xBF".b.freeze
  SETA = '-->'.freeze

  def self.para(id, pasta: PASTA)
    return unless File.exist?(pasta.join("#{id}.mp4"))

    versao_da_legenda, duracao = legenda(pasta.join("#{id}.vtt"))
    { 'arquivo' => arquivo(id, 'mp4', pasta), 'legenda' => versao_da_legenda && "#{URL}#{id}.vtt?v=#{versao_da_legenda}",
      'poster' => arquivo(id, 'jpg', pasta), 'duracao' => duracao }
  end

  def self.arquivo(id, extensao, pasta)
    caminho = pasta.join("#{id}.#{extensao}")
    "#{URL}#{id}.#{extensao}?v=#{versao(caminho)}" if File.exist?(caminho)
  end

  # Ler o vídeo inteiro a cada pedido da tela sairia caro: a versão fica guardada enquanto o arquivo
  # não muda (mesmo caminho, mesma data de modificação).
  def self.versao(caminho)
    versoes[chave(caminho)] ||= Digest::SHA256.file(caminho).hexdigest[0, TAMANHO_DA_VERSAO]
  end

  def self.versoes
    @versoes ||= {}
  end

  # A legenda é lida uma vez só para as duas coisas que saem dela, a versão do endereço e a duração; e,
  # como a versão dos outros arquivos, fica guardada enquanto o arquivo não muda.
  def self.legenda(caminho)
    return [nil, nil] unless File.exist?(caminho)

    legendas[chave(caminho)] ||= begin
      conteudo = File.binread(caminho)
      [Digest::SHA256.hexdigest(conteudo)[0, TAMANHO_DA_VERSAO], duracao_de(conteudo)]
    end
  end

  def self.legendas
    @legendas ||= {}
  end

  def self.chave(caminho) = [caminho.to_s, File.mtime(caminho).to_r]

  # Última linha de tempo ("00:01:02.500 --> 00:01:05.250 align:start"): o primeiro pedaço depois da seta.
  def self.duracao_de(conteudo)
    linha = conteudo.delete_prefix(BOM).split("\n").reverse.find { |texto| texto.include?(SETA) }
    return if linha.nil?

    segundos(linha.split(SETA, 2).last.split.first.to_s)
  end

  # "hh:mm:ss.mmm" ou "mm:ss.mmm" em segundos inteiros; qualquer outra forma é tempo ilegível.
  def self.segundos(tempo)
    partes = tempo.split(':').map { |parte| Float(parte, exception: false) }
    return unless partes.size.between?(2, 3) && partes.all?

    partes.reduce(0) { |total, parte| (total * 60) + parte }.round
  end
  private_class_method :arquivo, :versao, :versoes, :legenda, :legendas, :chave, :duracao_de, :segundos
end
