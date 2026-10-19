# #1426 (revisão adversarial) — uma página de PDF vira PNG pelo ImageMagick, com limite de recurso e tempo máximo, para o
# OCR do PDF escaneado. O programa é chamado direto (sem shell), num grupo de processos próprio (o ImageMagick chama o
# ghostscript): estourado o tempo, o grupo inteiro é encerrado e esperado, sem processo órfão.
#
# Limites (`-limit`, antes da entrada para valerem na leitura): memória e mapa em disco do cache de pixels, disco, área
# (40 MP, o mesmo teto da foto) e tempo. Quem chama confere antes o tamanho da página (MediaBox × UserUnit × DPI).
#
# A entrada vai com o prefixo `pdf:`, que obriga o ImageMagick a usar o leitor de PDF em vez de adivinhar o formato pelo
# conteúdo; e só vai se o arquivo começa com `%PDF-` no byte 0. Um PostScript (ou outro formato que o ghostscript
# interpreta) com `%PDF-` mais adiante não é rasterizado. Sugestão de infra, fora deste PR: no policy.xml da imagem,
# liberar só PDF e PNG (`<policy domain="coder" rights="none" pattern="*" />` + `rights="read|write" pattern="{PDF,PNG}"`).
module Autonomia::Agents::Knowledge::Processors::Rasterizacao
  DPI = 300
  TEMPO_MAXIMO = 60 # segundos por página; uma página A4 a 300 DPI leva 1 a 3 s.
  LIMITES = %w[-limit memory 256MiB -limit map 512MiB -limit disk 1GiB -limit area 40MP -limit time 60].freeze
  # ImageMagick 7 (`magick`, o da imagem Alpine) e o nome antigo (`convert`, ImageMagick 6).
  PROGRAMAS = %w[magick convert].freeze

  CABECALHO_PDF = '%PDF-'.b.freeze

  class Falhou < StandardError; end

  module_function

  # Rasteriza a página `indice` (a partir de 0) num PNG temporário e cede o caminho dele; o PNG some ao fim.
  def pagina(pdf, indice, tempo: TEMPO_MAXIMO)
    raise Falhou, 'nao_e_pdf' unless pdf?(pdf)

    Dir.mktmpdir('autonomia_pdf') do |pasta|
      png = File.join(pasta, 'pagina.png')
      rodar([*LIMITES, '-density', DPI.to_s, "pdf:#{pdf}[#{indice}]", '-background', 'white', '-alpha', 'remove', png], tempo)
      raise Falhou, 'rasterizacao_sem_saida' unless File.exist?(png)

      yield png
    end
  end

  def pdf?(caminho)
    File.binread(caminho, CABECALHO_PDF.bytesize) == CABECALHO_PDF
  rescue SystemCallError
    false
  end

  def rodar(argumentos, tempo)
    PROGRAMAS.each do |programa|
      return executar([programa, *argumentos], tempo)
    rescue Errno::ENOENT
      next
    end
    raise Falhou, 'imagemagick_ausente'
  end

  def executar(comando, tempo)
    pid = Process.spawn(*comando, in: File::NULL, out: File::NULL, err: File::NULL, pgroup: true)
    espera = Process.detach(pid)
    encerrar!(espera) unless espera.join(tempo)
    raise Falhou, "imagemagick_exit_#{espera.value.exitstatus}" unless espera.value.success?
  end

  def encerrar!(espera)
    matar(espera.pid)
    espera.join
    raise Falhou, 'rasterizacao_timeout'
  end

  def matar(pid)
    Process.kill('KILL', -pid)
  rescue Errno::ESRCH
    nil
  end
end
