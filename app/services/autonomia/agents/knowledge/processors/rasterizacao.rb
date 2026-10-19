# #1426 (revisão adversarial) — uma página de PDF vira PNG pelo ImageMagick, com limite de recurso e tempo máximo, para o
# OCR do PDF escaneado. O programa é chamado direto (sem shell), num grupo de processos próprio (o ImageMagick chama o
# ghostscript): estourado o tempo, o grupo inteiro é encerrado e esperado, sem processo órfão.
#
# Limites (`-limit`, antes da entrada para valerem na leitura): memória e mapa em disco do cache de pixels, disco, área
# (40 MP, o mesmo teto da foto) e tempo. Quem chama confere antes o tamanho da página (MediaBox × UserUnit × DPI).
#
# A entrada vai com o prefixo `pdf:` (o ImageMagick usa o leitor de PDF) e só vai quando o cabeçalho `%PDF-` está nos
# primeiros 1024 bytes, como os leitores de PDF aceitam, e não há `%!` (a marca do PostScript) antes dele. O `pdf:` NÃO
# basta: medido em 19/10 (Alpine 3.21, ImageMagick 7.1.1-41, ghostscript 10.05.1), um arquivo que começa com `%!PS`
# (mesmo depois de espaço, linha vazia ou Ctrl-D) e traz `%PDF-` adiante é executado pelo ghostscript como PostScript
# com `pdf:`. Lixo ou comentário comum antes de `%PDF-` é lido como PDF, sem executar nada.
#
# Sugestão de infra, fora deste PR: no policy.xml da imagem, liberar só PDF e PNG
# (`<policy domain="coder" rights="none" pattern="*" />` + `rights="read|write" pattern="{PDF,PNG}"`).
module Autonomia::Agents::Knowledge::Processors::Rasterizacao
  DPI = 300
  TEMPO_MAXIMO = 60 # segundos por página; uma página A4 a 300 DPI leva 1 a 3 s.
  LIMITES = %w[-limit memory 256MiB -limit map 512MiB -limit disk 1GiB -limit area 40MP -limit time 60].freeze
  # ImageMagick 7 (`magick`, o da imagem Alpine) e o nome antigo (`convert`, ImageMagick 6).
  PROGRAMAS = %w[magick convert].freeze

  CABECALHO_PDF = '%PDF-'.b.freeze
  MARCA_POSTSCRIPT = '%!'.b.freeze
  ONDE_PROCURAR_O_CABECALHO = 1024

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
    inicio = File.binread(caminho, ONDE_PROCURAR_O_CABECALHO).to_s
    cabecalho = inicio.index(CABECALHO_PDF)
    !cabecalho.nil? && inicio.byteslice(0, cabecalho).exclude?(MARCA_POSTSCRIPT)
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
