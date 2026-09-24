require 'rails_helper'

RSpec.describe Autonomia::Prospecting::DecisionMakerType do
  it 'tem os 11 perfis do Orth e só o Proprietário disponível' do
    expect(described_class::ALL.size).to eq(11)
    expect(described_class::AVAILABLE).to eq(['owner'])
    expect(described_class::DEFAULT).to eq('owner')
  end

  it 'mantém o Proprietário e troca vazio, perfil em breve ou desconhecido pelo padrão' do
    expect(%w[owner ceo xpto].map { |value| described_class.normalize(value) } + [described_class.normalize(nil)])
      .to eq(%w[owner owner owner owner])
  end
end
