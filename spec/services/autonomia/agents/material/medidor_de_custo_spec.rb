require 'rails_helper'

# #1426 (tema 4b) — o medidor soma o custo REAL das chamadas da rodada (o aviso `crm.ai_usage` do UsageRecorder), só da
# thread dela, e diz se a próxima chamada cabe no teto antes de fazê-la.
RSpec.describe Autonomia::Agents::Material::MedidorDeCusto do
  def aviso(custo)
    ActiveSupport::Notifications.instrument(Crm::Ai::UsageRecorder::EVENT_NAME, cost: custo)
  end

  it 'soma o custo real de cada chamada medida' do
    medidor = described_class.new

    medidor.medir(:resposta) do
      aviso(0.02)
      aviso(0.01)
    end
    medidor.medir(:juiz) { aviso(0.004) }

    expect(medidor.gasto).to be_within(0.000001).of(0.034)
  end

  it 'não conta o que outra thread gastou no mesmo tempo' do
    medidor = described_class.new

    medidor.medir(:resposta) do
      Thread.new { aviso(5.0) }.join
      aviso(0.02)
    end

    expect(medidor.gasto).to be_within(0.000001).of(0.02)
  end

  it 'não conta o que acontece fora da medição' do
    medidor = described_class.new
    aviso(1.0)

    medidor.medir(:juiz) { aviso(0.01) }
    aviso(1.0)

    expect(medidor.gasto).to be_within(0.000001).of(0.01)
  end

  it 'chamada sem custo conhecido (modelo sem preço, falha sem uso) conta a estimativa, nunca zero' do
    medidor = described_class.new

    medidor.medir(:resposta) { nil }

    expect(medidor.gasto).to eq(described_class::ESTIMATIVA_INICIAL[:resposta])
  end

  it 'conta mesmo quando a chamada levanta' do
    medidor = described_class.new

    expect { medidor.medir(:juiz) { aviso(0.05).then { raise('falhou') } } }.to raise_error('falhou')
    expect(medidor.gasto).to be_within(0.000001).of(0.05)
  end

  it 'cabe? usa o maior custo já visto do tipo: para ANTES de passar do teto', :aggregate_failures do
    medidor = described_class.new(teto: 1.0)

    medidor.medir(:resposta) { aviso(0.4) }
    expect(medidor.cabe?(:resposta)).to be(true) # 0,4 + 0,4 = 0,8

    medidor.medir(:resposta) { aviso(0.4) }
    expect(medidor.cabe?(:resposta)).to be(false) # 0,8 + 0,4 = 1,2 > 1,0
    expect(medidor.cabe?(:juiz)).to be(true) # 0,8 + 0,03
  end

  it 'o teto padrão é US$ 2' do
    expect(described_class::TETO_USD).to eq(2.0)
  end
end
