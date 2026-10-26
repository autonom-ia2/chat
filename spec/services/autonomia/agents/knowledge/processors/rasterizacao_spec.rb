require 'rails_helper'

# #1426 (revisão adversarial) — a página do PDF vira PNG pelo ImageMagick com limite de recurso e tempo máximo, sem deixar
# processo órfão. Um `magick`/`convert` falso no PATH faz o papel do binário.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Rasterizacao do
  let(:pasta) { Dir.mktmpdir }
  let(:argumentos) { File.join(pasta, 'argumentos') }

  after { FileUtils.remove_entry(pasta) }

  # O falso grava os argumentos e cria o PNG no último deles, como o ImageMagick.
  def programa_falso(nome, corpo = nil)
    caminho = File.join(pasta, nome)
    corpo ||= "printf '%s\\n' \"$@\" > #{argumentos}; for ultimo; do :; done; printf 'png' > \"$ultimo\""
    File.write(caminho, "#!/bin/sh\n#{corpo}\n")
    File.chmod(0o755, caminho)
  end

  def documento(conteudo = "%PDF-1.4\n%%EOF\n")
    File.join(pasta, 'doc.pdf').tap { |caminho| File.binwrite(caminho, conteudo) }
  end

  def com_path(path, &)
    with_modified_env(PATH: path, &)
  end

  def rasterizar(tempo: described_class::TEMPO_MAXIMO)
    com_path("#{pasta}:/usr/bin:/bin") do
      described_class.pagina(documento, 2, tempo: tempo) { |png| File.read(png) }
    end
  end

  it 'rasterizes one page at 300 DPI with the resource limits before the input, forcing the PDF reader' do
    programa_falso('magick')

    expect(rasterizar).to eq('png')

    lidos = File.readlines(argumentos, chomp: true)
    entrada = "pdf:#{File.join(pasta, 'doc.pdf')}[2]"
    expect(lidos.first(described_class::LIMITES.size)).to eq(described_class::LIMITES)
    expect(lidos).to include('-density', '300', entrada)
    expect(lidos.index(entrada)).to be > lidos.index('-density')
  end

  def recusado?(conteudo)
    programa_falso('magick')
    com_path("#{pasta}:/usr/bin:/bin") { described_class.pagina(documento(conteudo), 0) { nil } }
    false
  rescue described_class::Falhou => e
    e.message == 'nao_e_pdf' && !File.exist?(argumentos)
  end

  it 'accepts a file that starts with %PDF- at byte 0' do
    expect(recusado?("%PDF-1.4\n%%EOF\n")).to be(false)
  end

  # S2 — qualquer coisa antes de %PDF- é recusada e o ImageMagick nunca roda: lixo, comentário, BOM, DOS EPS, PJL, PostScript
  # em ASCII puro e as marcas %! (medido no ghostscript 10.05.1: %!PS antes de %PDF- é executado como PostScript com `pdf:`).
  it 'refuses anything before the PDF header, and never runs ImageMagick' do
    ["% comentario\n%PDF-1.4\n", "LIXO\n%PDF-1.4\n", "\xEF\xBB\xBF%PDF-1.4\n", "\xC5\xD0\xD3\xC6\x20\x00\x00\x00%PDF-1.4\n",
     "\e%-12345X@PJL ENTER LANGUAGE = PDF\n%PDF-1.4\n", "(x) print\n%PDF-1.4\n",
     "%!PS-Adobe-3.0\n%PDF-1.4\n", " %!PS\n%PDF-1.4\n", "\n%!PS\n%PDF-1.4\n", "\x04%!PS\n%PDF-1.4\n", "LIXO\n%!PS\n%PDF-1.4\n"]
      .each { |conteudo| expect(recusado?(conteudo)).to be(true), conteudo.inspect }
  end

  it 'refuses an empty or missing file' do
    expect { described_class.pagina(documento(''), 0) { nil } }.to raise_error(described_class::Falhou, 'nao_e_pdf')
    expect { described_class.pagina(File.join(pasta, 'nada.pdf'), 0) { nil } }.to raise_error(described_class::Falhou, 'nao_e_pdf')
  end

  it 'uses the old ImageMagick name when magick is not installed' do
    programa_falso('convert')

    expect(rasterizar).to eq('png')
  end

  it 'stops ImageMagick after the time limit and leaves no process behind' do
    marca = File.join(pasta, 'pid')
    programa_falso('magick', "echo $$ > #{marca}; exec sleep 30")

    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { rasterizar(tempo: 1) }.to raise_error(described_class::Falhou, 'rasterizacao_timeout')

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 10
    expect { Process.kill(0, File.read(marca).to_i) }.to raise_error(Errno::ESRCH)
  end

  it 'fails when ImageMagick refuses the page' do
    programa_falso('magick', 'exit 1')

    expect { rasterizar }.to raise_error(described_class::Falhou, 'imagemagick_exit_1')
  end

  it 'fails clearly when ImageMagick is not installed' do
    expect { com_path(pasta) { described_class.pagina(documento, 0) { nil } } }
      .to raise_error(described_class::Falhou, 'imagemagick_ausente')
  end

  # O neto não é filho do Ruby: depois do SIGKILL ele morre e o init o colhe quando puder; até lá o pid ainda existe.
  # Por isso a conferência espera ele sumir, com prazo, em vez de olhar uma vez só logo depois do kill (#2234).
  def sumiu?(pid, prazo: 5)
    limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + prazo
    loop do
      Process.kill(0, pid)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > limite

      sleep 0.05
    end
  rescue Errno::ESRCH
    true
  end

  # V4 — o tempo estourado mata o GRUPO (o ImageMagick chama o ghostscript): o filho também morre.
  it 'kills the whole process group on timeout, children included' do
    filho = File.join(pasta, 'filho')
    programa_falso('magick', "sleep 30 & echo $! > #{filho}; wait")

    expect { rasterizar(tempo: 1) }.to raise_error(described_class::Falhou, 'rasterizacao_timeout')
    neto = File.read(filho).to_i
    expect(sumiu?(neto)).to be(true), "o neto #{neto} ainda existe 5 s depois do kill do grupo"
  end

  it 'removes the temporary page when the reading fails' do
    programa_falso('magick')
    lida = nil
    quebra = proc do |png|
      lida = png
      raise 'ocr quebrou'
    end

    expect { com_path("#{pasta}:/usr/bin:/bin") { described_class.pagina(documento, 0, &quebra) } }
      .to raise_error(RuntimeError, 'ocr quebrou')
    expect(File).not_to exist(File.dirname(lida))
  end
end
