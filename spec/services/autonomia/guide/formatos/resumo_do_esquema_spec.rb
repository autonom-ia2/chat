require 'rails_helper'

# O resumo de um campo JSON que é objeto com chaves, sem valor fechado nem ramo: a bateria (I04)
# mostrou "Campo leitura:" vazio, e o Guia não conseguiu montar a vigia.
RSpec.describe Autonomia::Guide::Formatos::ResumoDoEsquema do
  subject(:resumo) { described_class.new('leitura', Autonomia::Guide::Vigia::LEITURA) }

  it 'lista cada chave do objeto com tipo, se é obrigatória e o que ela é', :aggregate_failures do
    texto = resumo.texto(2_500)

    expect(texto).to include('- rota (string, obrigatório): A leitura da conta')
    expect(texto).to include('- medida (object, obrigatório): O número tirado da leitura.')
    expect(texto).to include('- parametros (object)')
  end

  it 'devolve a chave pedida pelo nome quando ela não é um ramo' do
    expect(resumo.ramo('medida', 2_500)).to start_with("Campo leitura.medida:\n").and include('"contagem"')
  end

  it 'chave que não existe continua sem resposta' do
    expect(resumo.ramo('recurso', 2_500)).to be_nil
  end
end
