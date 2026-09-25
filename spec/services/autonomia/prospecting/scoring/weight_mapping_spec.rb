require 'rails_helper'

# Pesos de 8 sinais (perfil do catálogo ou customizado da conta) viram os 6 componentes do Orth (#681, decisão do
# Rodrigo de 25/09): reviews_count vira volume, google_rank e query_relevance saem, e o resto volta a somar 100.
RSpec.describe Autonomia::Prospecting::Scoring::WeightMapping do
  it 'o perfil padrão de hoje vira 28/11/22/17/11/11' do
    mapped = described_class.from_legacy(Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS)

    expect(mapped).to eq('website' => 28, 'phone' => 11, 'rating' => 22, 'volume' => 17, 'activity' => 11, 'photos' => 11)
  end

  it 'pesos personalizados que já somam 100 sem os dois sinais que saem ficam iguais' do
    legacy = { 'website' => 40, 'phone' => 0, 'rating' => 30, 'reviews_count' => 10, 'activity' => 0, 'photos' => 20,
               'google_rank' => 50, 'query_relevance' => 50 }

    expect(described_class.from_legacy(legacy))
      .to eq('website' => 40, 'phone' => 0, 'rating' => 30, 'volume' => 10, 'activity' => 0, 'photos' => 20)
  end

  it 'a sobra do arredondamento vai para o site, como no normalizeWeights do Orth' do
    legacy = { 'website' => 1, 'phone' => 1, 'rating' => 1, 'reviews_count' => 0, 'activity' => 0, 'photos' => 0 }

    expect(described_class.from_legacy(legacy))
      .to eq('website' => 34, 'phone' => 33, 'rating' => 33, 'volume' => 0, 'activity' => 0, 'photos' => 0)
  end

  it 'chave que falta vem do padrão de hoje, como no LeadScorer' do
    mapped = described_class.from_legacy(website: 50)

    expect(mapped).to eq('website' => 43, 'phone' => 9, 'rating' => 17, 'volume' => 13, 'activity' => 9, 'photos' => 9)
    expect(mapped.values.sum).to eq(100)
  end

  it 'se só google_rank e query_relevance pesavam, usa o padrão do Orth' do
    legacy = Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.transform_values { 0 }.merge('google_rank' => 60, 'query_relevance' => 40)

    expect(described_class.from_legacy(legacy)).to eq(Autonomia::Prospecting::Scoring::EffectiveWeights::DEFAULT)
  end
end
