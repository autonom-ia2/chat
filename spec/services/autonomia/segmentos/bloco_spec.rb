require 'rails_helper'

# Contrato do bloco de segmento (tema 8, #1429). Hoje `for_segmento` e `versao` são nil; estes exemplos continuam
# valendo quando o lote 6 preencher o texto. "Nenhuma frase pronta de cliente" é regra de conteúdo, escrita no arquivo.
RSpec.describe Autonomia::Segmentos::Bloco do
  let(:segmento) { 'seguros/corretora' }

  it 'for_segmento returns nil or a String within the ceiling' do
    texto = described_class.for_segmento(segmento)

    expect(texto).to be_nil.or(be_a(String))
    expect(texto.to_s.bytesize).to be <= described_class::TEXTO_DA_BASE_MAX
  end

  it 'is stable between calls for the same segmento' do
    texto = described_class.for_segmento(segmento)
    versao = described_class.versao(segmento)

    expect(described_class.for_segmento(segmento.dup)).to eq(texto)
    expect(described_class.versao(segmento.dup)).to eq(versao)
  end

  it 'versao returns nil or a String' do
    expect(described_class.versao(segmento)).to be_nil.or(be_a(String))
  end

  # Trava do contrato: o texto e a versão dependem só do segmento (um argumento obrigatório).
  it 'depends only on the segmento' do
    %i[for_segmento versao].each do |metodo|
      obrigatorios = described_class.method(metodo).parameters.count { |tipo, _| %i[req keyreq].include?(tipo) }
      expect(obrigatorios).to eq(1)
    end
  end

  it 'no longer has for(account): nada lê o bloco pela conta' do
    expect(described_class).not_to respond_to(:for)
  end
end
