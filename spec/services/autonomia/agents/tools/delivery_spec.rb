require 'rails_helper'

# O RESULTADO DE COTAÇÃO QUE O MODELO LEU NO TURNO (fatia 3 do #420): é contra ele que o `Answerer` confere a fala.
RSpec.describe Autonomia::Agents::Tools::Delivery do
  let(:delivery) { described_class.new(conversation: nil, agent_inbox: nil, origin_message_id: 1) }
  let(:dados) { Autonomia::Agents::ConferenciaDePrecos::Dados }

  it 'começa sem resultado do turno' do
    expect(delivery.resultado_do_turno).to be_nil
  end

  it 'duas chamadas no turno somam, na ordem em que vieram' do
    delivery.registrar_resultado(dados.new(texto: 'Porto', seguradoras: ['Porto'], comparativo: false))
    delivery.registrar_resultado(dados.new(texto: 'Allianz', seguradoras: ['Allianz'], comparativo: true))

    expect(delivery.resultado_do_turno.texto).to eq("Porto\nAllianz")
    expect(delivery.resultado_do_turno.seguradoras).to eq(%w[Porto Allianz])
    expect(delivery.resultado_do_turno.comparativo).to be(true)
  end
end
