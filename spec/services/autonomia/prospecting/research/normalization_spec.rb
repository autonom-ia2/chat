require 'rails_helper'

# Normalização de texto da Receita (como normalization.ts do Orth): maiúsculas, sem acento, separadores viram espaço,
# espaços colapsados. Sem regex.
RSpec.describe Autonomia::Prospecting::Research::Normalization do
  it 'normaliza qualificação e natureza jurídica para comparação por tabela' do
    expect(described_class.key(' Sócio-Administrador ')).to eq('SOCIO ADMINISTRADOR')
    expect(described_class.key('Empresário (Individual)')).to eq('EMPRESARIO INDIVIDUAL')
    expect(described_class.key("JOÃO  da\tCONCEIÇÃO")).to eq('JOAO DA CONCEICAO')
    expect(described_class.key(nil)).to eq('')
  end

  it 'extrai só os dígitos' do
    expect(described_class.digits('11.222.333/0001-81')).to eq('11222333000181')
    expect(described_class.digits(4_721_102)).to eq('4721102')
  end

  it 'separa os números de uma faixa etária' do
    expect(described_class.numbers('Entre 13 a 20 anos')).to eq([13, 20])
    expect(described_class.numbers('Não se aplica')).to eq([])
  end
end
