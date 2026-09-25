require 'rails_helper'

# Porte de adaptWeightsToContext (score.ts do Orth, #681): o filtro ativo zera ou reduz o peso do sinal que ele já
# garante, e o que sobra volta a somar 100. Filtros no formato de advanced_filters da busca ('yes'/'no', números em
# texto); reviews_min é o userRatingCountMin do Orth.
RSpec.describe Autonomia::Prospecting::Scoring::EffectiveWeights do
  let(:defaults) { described_class::DEFAULT }

  it 'o padrão é o do Orth e soma 100' do
    expect(defaults).to eq('website' => 30, 'phone' => 10, 'rating' => 20, 'volume' => 15, 'activity' => 10, 'photos' => 15)
    expect(defaults.values.sum).to eq(100)
  end

  it 'sem filtro devolve os pesos como vieram' do
    expect(described_class.for(defaults, {})).to eq(defaults)
    expect(described_class.for(defaults, nil)).to eq(defaults)
  end

  it 'completa a chave que faltar com o padrão do Orth' do
    expect(described_class.for({ 'website' => 50, 'phone' => 0 }, {})).to eq(
      'website' => 45, 'phone' => 0, 'rating' => 18, 'volume' => 14, 'activity' => 9, 'photos' => 14
    )
  end

  it 'filtro de site, com sim ou não, zera o site e renormaliza para 100' do
    %w[yes no].each do |value|
      weights = described_class.for(defaults, { 'has_website' => value })

      expect(weights['website']).to eq(0)
      expect(weights).to eq('website' => 0, 'phone' => 14, 'rating' => 30, 'volume' => 21, 'activity' => 14, 'photos' => 21)
      expect(weights.values.sum).to eq(100)
    end
  end

  it 'filtro de telefone e de fotos zeram o próprio peso' do
    expect(described_class.for(defaults, { 'has_phone' => 'yes' })['phone']).to eq(0)
    expect(described_class.for(defaults, { 'has_photos' => 'no' })['photos']).to eq(0)
  end

  it 'nota mínima de 4.5 corta o rating para 15%, de 4.0 para 40%' do
    expect(described_class.for(defaults, { 'rating_min' => '4.5' })['rating']).to eq(4)
    expect(described_class.for(defaults, { 'rating_min' => '4.0' })['rating']).to eq(9)
    expect(described_class.for(defaults, { 'rating_min' => '3.5' })).to eq(defaults)
  end

  it 'nota máxima de 3.0 ou menos corta o rating para 30%' do
    expect(described_class.for(defaults, { 'rating_max' => '3' })['rating']).to eq(7)
    expect(described_class.for(defaults, { 'rating_max' => '3.5' })).to eq(defaults)
  end

  it 'mínimo de 50 avaliações zera o volume, de 20 corta para 40%' do
    expect(described_class.for(defaults, { 'reviews_min' => '50' })['volume']).to eq(0)
    expect(described_class.for(defaults, { 'reviews_min' => '20' })['volume']).to eq(7)
    expect(described_class.for(defaults, { 'reviews_min' => '10' })).to eq(defaults)
  end

  it 'a sobra do arredondamento vai para o maior peso' do
    weights = described_class.for(defaults, { 'has_website' => 'yes', 'has_phone' => 'yes', 'has_photos' => 'yes' })

    expect(weights).to eq('website' => 0, 'phone' => 0, 'rating' => 45, 'volume' => 33, 'activity' => 22, 'photos' => 0)
    expect(weights.values.sum).to eq(100)
  end

  it 'se o filtro zerar tudo, volta aos pesos de entrada' do
    only_site = defaults.transform_values { 0 }.merge('website' => 100)

    expect(described_class.for(only_site, { 'has_website' => 'yes' })).to eq(only_site)
  end

  it 'filtro em branco ou com valor fora de sim ou não não conta' do
    expect(described_class.for(defaults, { 'has_website' => '', 'has_phone' => 'talvez', 'rating_min' => '' })).to eq(defaults)
  end
end
