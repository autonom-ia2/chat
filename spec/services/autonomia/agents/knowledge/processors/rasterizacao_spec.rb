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

  # V4: um PostScript com %PDF- depois do byte 0 seria interpretado pelo ghostscript; nunca chega ao ImageMagick.
  it 'refuses a file that does not start with %PDF- and never runs ImageMagick' do
    programa_falso('magick')
    postscript = documento("%!PS-Adobe-3.0\n%PDF-1.4\n(x) print\n")

    expect { com_path("#{pasta}:/usr/bin:/bin") { described_class.pagina(postscript, 0) { nil } } }
      .to raise_error(described_class::Falhou, 'nao_e_pdf')
    expect(File).not_to exist(argumentos)
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

  # V4 — o tempo estourado mata o GRUPO (o ImageMagick chama o ghostscript): o filho também morre.
  it 'kills the whole process group on timeout, children included' do
    filho = File.join(pasta, 'filho')
    programa_falso('magick', "sleep 30 & echo $! > #{filho}; wait")

    expect { rasterizar(tempo: 1) }.to raise_error(described_class::Falhou, 'rasterizacao_timeout')
    expect { Process.kill(0, File.read(filho).to_i) }.to raise_error(Errno::ESRCH)
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
