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

  def com_path(path, &)
    with_modified_env(PATH: path, &)
  end

  def rasterizar(tempo: described_class::TEMPO_MAXIMO)
    com_path("#{pasta}:/usr/bin:/bin") do
      described_class.pagina('/tmp/doc.pdf', 2, tempo: tempo) { |png| File.read(png) }
    end
  end

  it 'rasterizes one page at 300 DPI with the resource limits before the input' do
    programa_falso('magick')

    expect(rasterizar).to eq('png')

    lidos = File.readlines(argumentos, chomp: true)
    expect(lidos.first(described_class::LIMITES.size)).to eq(described_class::LIMITES)
    expect(lidos).to include('-density', '300', '/tmp/doc.pdf[2]')
    expect(lidos.index('/tmp/doc.pdf[2]')).to be > lidos.index('-density')
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
    expect { com_path(pasta) { described_class.pagina('/tmp/doc.pdf', 0) { nil } } }
      .to raise_error(described_class::Falhou, 'imagemagick_ausente')
  end
end
