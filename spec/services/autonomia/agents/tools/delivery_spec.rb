require 'rails_helper'

# OS ANEXOS DO TURNO (fatia 2 do #420): o texto escrito pelo código que o `Operate::Responder` entrega depois da resposta.
RSpec.describe Autonomia::Agents::Tools::Delivery do
  let(:delivery) { described_class.new(conversation: nil, agent_inbox: nil, origin_message_id: 1) }

  it 'começa sem anexo' do
    expect(delivery.anexos).to eq([])
    expect(delivery.anexo('lista_de_precos')).to be_nil
  end

  it 'entrega os anexos na ordem em que as chaves entraram, com os dados de cada um' do
    delivery.anexar('lista_de_precos', 'Porto Seguro', dados: ['8'])
    delivery.anexar('outra', 'segundo anexo')

    expect(delivery.anexos).to eq(['Porto Seguro', 'segundo anexo'])
    expect(delivery.anexo(:lista_de_precos).dados).to eq(['8'])
  end

  # A ferramenta chamada duas vezes no mesmo turno troca o próprio anexo, no lugar em que ele entrou: um anexo só.
  it 'a mesma chave troca o anexo no mesmo lugar' do
    delivery.anexar('lista_de_precos', 'Porto Seguro', dados: ['8'])
    delivery.anexar('outra', 'segundo anexo')
    delivery.anexar('lista_de_precos', 'Porto Seguro e Allianz', dados: %w[8 5])

    expect(delivery.anexos).to eq(['Porto Seguro e Allianz', 'segundo anexo'])
    expect(delivery.anexo('lista_de_precos').dados).to eq(%w[8 5])
  end

  it 'anexo em branco não é entregue' do
    delivery.anexar('lista_de_precos', '  ')

    expect(delivery.anexos).to eq([])
  end
end
