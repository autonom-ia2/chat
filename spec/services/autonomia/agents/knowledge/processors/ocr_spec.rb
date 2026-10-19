require 'rails_helper'

# #1426 (revisão adversarial) — o tesseract roda com tempo máximo e sem deixar processo órfão; sem o binário, o OCR fica
# indisponível com motivo claro. Um tesseract falso no PATH faz o papel do binário.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Ocr do
  let(:pasta) { Dir.mktmpdir }

  after { FileUtils.remove_entry(pasta) }

  def tesseract_falso(corpo)
    caminho = File.join(pasta, 'tesseract')
    File.write(caminho, "#!/bin/sh\n#{corpo}\n")
    File.chmod(0o755, caminho)
  end

  def com_path(path, &)
    with_modified_env(PATH: path, &)
  end

  it 'returns what tesseract printed, reading the file in Portuguese' do
    tesseract_falso('echo "$1|$2|$3|$4"')

    saida = com_path("#{pasta}:/usr/bin:/bin") { described_class.ler('/tmp/foto.png') }

    expect(saida.strip).to eq('/tmp/foto.png|stdout|-l|por')
  end

  it 'stops tesseract after the time limit and leaves no process behind' do
    marca = File.join(pasta, 'pid')
    tesseract_falso("echo $$ > #{marca}; exec sleep 30")

    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { com_path("#{pasta}:/usr/bin:/bin") { described_class.ler('/tmp/foto.png', tempo: 1) } }
      .to raise_error(described_class::Indisponivel, 'tesseract_timeout')

    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio).to be < 10
    pid = File.read(marca).to_i
    expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
  end

  it 'reports a refusal by tesseract' do
    tesseract_falso('exit 1')

    expect { com_path("#{pasta}:/usr/bin:/bin") { described_class.ler('/tmp/foto.png') } }
      .to raise_error(described_class::Falhou)
  end

  it 'is unavailable when tesseract is not installed' do
    expect { com_path(pasta) { described_class.ler('/tmp/foto.png') } }
      .to raise_error(described_class::Indisponivel, 'tesseract_missing')
  end
end
