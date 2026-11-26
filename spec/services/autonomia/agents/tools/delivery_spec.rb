require 'rails_helper'

# O RESULTADO DE COTAÇÃO QUE O MODELO LEU NO TURNO (fatia 3 do #420): é contra ele que o `Answerer` confere a fala.
RSpec.describe Autonomia::Agents::Tools::Delivery do
  let(:delivery) { described_class.new(conversation: nil, agent_inbox: nil, origin_message_id: 1) }
  let(:dados) { Autonomia::Agents::ConferenciaDePrecos::Dados }

  # O TURNO NOS DOIS CAMINHOS (revisão da chat#718): é a chave das notas na hora (`Insurance::NotaNaHora`).
  describe '#turno' do
    let(:run) { instance_double(Autonomia::Agents::ToolRun, id: 42) }

    def turno(**opcoes)
      described_class.new(conversation: nil, agent_inbox: nil, **opcoes).turno
    end

    it 'no turno de mensagem, é a mensagem de origem' do
      expect(turno(origin_message_id: 7)).to eq('mensagem:7')
    end

    it 'no turno de evento, é a execução e o tipo do evento, e muda com qualquer um dos dois' do
      expect(turno(evento: 'concluida', execucao_do_evento: run)).to eq('evento:42:concluida')
      expect(turno(evento: 'falhou', execucao_do_evento: run)).not_to eq(turno(evento: 'concluida', execucao_do_evento: run))
    end

    # #3246b: a marca do evento sem execução (o aviso de pagamento da Bia) é opcional; sem ela, o turno da Lia não muda.
    it 'no turno de evento sem marca, o turno da Lia é exatamente o de antes (marca nil ou vazia)' do
      expect(turno(evento: 'concluida', execucao_do_evento: run, marca_do_evento: nil)).to eq('evento:42:concluida')
      expect(turno(evento: 'concluida', execucao_do_evento: run, marca_do_evento: '')).to eq('evento:42:concluida')
      expect(turno(evento: 'concluida')).to eq('evento::concluida')
    end

    it 'no turno de evento com marca, o turno é a marca, e o turno de mensagem continua vencendo' do
      marca = 'viagem:9:1764158000:pagamento_confirmado'
      expect(turno(evento: 'pagamento_confirmado', marca_do_evento: marca)).to eq(marca)
      expect(turno(evento: 'pagamento_confirmado', marca_do_evento: marca, origin_message_id: 7)).to eq('mensagem:7')
      expect(described_class.new(conversation: nil, agent_inbox: nil, evento: 'x', marca_do_evento: marca)).to be_turno_de_evento
    end

    it 'sem nenhum dos dois, é um valor deste objeto: estável nele, diferente em outro' do
      sem = described_class.new(conversation: nil, agent_inbox: nil)
      primeiro = sem.turno

      expect(sem.turno).to eq(primeiro)
      expect(primeiro).not_to eq(turno)
    end
  end

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
