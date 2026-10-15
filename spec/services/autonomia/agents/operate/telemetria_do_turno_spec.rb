require 'rails_helper'

# A linha do turno (#1606, ponto 5): lista fechada de eventos, só ids, rótulos e milissegundos.
RSpec.describe Autonomia::Agents::Operate::TelemetriaDoTurno do
  def linha
    saida = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(saida)
    yield
    saida.string
  ensure
    Rails.logger = original
  end

  it 'escreve evento, conversa e os campos' do
    texto = linha { described_class.registrar(:assunto_esperou, conversation_id: 9, msg: 12, ms: 8100, origem: :responder) }

    expect(texto.strip).to eq('[autonomia][turno] assunto_esperou conv=9 msg=12 ms=8100 origem=responder')
  end

  it 'descarta valor que parece texto livre' do
    texto = linha { described_class.registrar(:devolucao, conversation_id: 9, destino: 'quero falar com alguém') }

    expect(texto).to include('destino=descartado')
    expect(texto).not_to include('quero')
  end

  it 'recusa evento fora da lista' do
    expect { described_class.registrar(:qualquer, conversation_id: 1) }.to raise_error(ArgumentError)
  end
end
