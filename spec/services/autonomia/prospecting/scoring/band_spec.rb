require 'rails_helper'

# As quatro faixas do card (prospectingPriority.js e priority-utils.tsx do Orth), pela prioridade de 0 a 100 (#681).
RSpec.describe Autonomia::Prospecting::Scoring::Band do
  it 'usa os limites do Orth: 75, 50 e 25' do
    expect([100, 75, 74.6, 50, 49, 25, 24, 0].map { |priority| described_class.code(priority) })
      .to eq(%w[very_hot very_hot very_hot high warm warm low low])
  end

  it 'arredonda como o anel do card antes de escolher a faixa' do
    expect(described_class.code(74.4)).to eq('high')
    expect(described_class.code(74.5)).to eq('very_hot')
  end

  it 'sem prioridade não tem faixa' do
    expect(described_class.code(nil)).to be_nil
  end

  it 'dá o título do card de cada faixa' do
    expect(%w[very_hot high warm low].map { |code| described_class.label(code) })
      .to eq(['Lead muito quente', 'Oportunidade alta', 'Lead morno', 'Prioridade baixa'])
  end
end
