require 'rails_helper'

# O comparativo cita a seguradora, o processo SUSEP e o link das condições gerais: os três têm de bater com a base do
# agente contratado, nunca com o que alguém lembrou.
RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::CondicoesGerais do
  let(:base) { File.read(described_class.arquivo) }
  let(:primeira_linha) { base.lines.first }

  it 'o link é o PDF oficial da 1ª linha da base' do
    expect(described_class.url).to start_with('https://www.universal-assistance.com/')
    expect(described_class.url).to end_with('.pdf')
    expect(primeira_linha).to include(described_class.url)
  end

  it 'o processo SUSEP é o da 1ª linha da base' do
    expect(primeira_linha).to include("processo SUSEP #{described_class::PROCESSO_SUSEP}")
  end

  it 'o registro na SUSEP diz em palavras de leigo o que a SUSEP é' do
    expect(described_class.registro_susep)
      .to eq("Registro na SUSEP (órgão do governo que fiscaliza seguros): #{described_class::PROCESSO_SUSEP}")
  end

  it 'a seguradora é a que a definição "Seguradora" das condições gerais nomeia' do
    expect(base).to include("**Seguradora:** É a #{described_class::SEGURADORA},")
  end
end
