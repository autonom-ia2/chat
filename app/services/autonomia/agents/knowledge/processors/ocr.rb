# O OCR da base (tesseract, pt-BR), num lugar só: o PDF escaneado lê cada página rasterizada por aqui, e a foto da criação
# (#1426) lê a própria imagem.
#
# #1426 (revisão adversarial) — o tesseract roda com tempo máximo. Ele é chamado direto (sem shell), num grupo de
# processos próprio: estourado o tempo, o grupo inteiro é encerrado e esperado, sem processo órfão segurando a fila.
# Quem chama confere antes que o arquivo é imagem (FotoConferida); o tesseract trata texto como lista de arquivos.
module Autonomia::Agents::Knowledge::Processors::Ocr
  IDIOMA = 'por'.freeze
  TEMPO_MAXIMO = 60 # segundos por imagem: uma foto de cardápio leva 2 a 10 s; um minuto já é sinal de problema.

  # Sem o tesseract na máquina, ou estourou o tempo: o OCR não está disponível para este arquivo.
  class Indisponivel < StandardError; end
  # O tesseract rodou e recusou o arquivo.
  class Falhou < StandardError; end

  module_function

  def ler(caminho, tempo: TEMPO_MAXIMO)
    Open3.popen2('tesseract', caminho.to_s, 'stdout', '-l', IDIOMA, err: File::NULL, pgroup: true) do |entrada, saida, espera|
      entrada.close
      leitura = Thread.new { saida.read }
      encerrar!(espera, leitura) unless espera.join(tempo)
      raise Falhou, "tesseract_exit_#{espera.value.exitstatus}" unless espera.value.success?

      leitura.value.to_s
    end
  rescue Errno::ENOENT
    raise Indisponivel, 'tesseract_missing'
  end

  def encerrar!(espera, leitura)
    matar(espera.pid)
    espera.join
    leitura.join
    raise Indisponivel, 'tesseract_timeout'
  end

  def matar(pid)
    Process.kill('KILL', -pid)
  rescue Errno::ESRCH
    nil
  end
end
