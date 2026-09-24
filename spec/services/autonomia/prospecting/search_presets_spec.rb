require 'rails_helper'

RSpec.describe Autonomia::Prospecting::SearchPresets do
  it 'tem as três jogadas de cada modo, com os ids do Orth' do
    expect(described_class::MODES_BY_ID).to eq(
      'vender-site' => 'gbp',
      'gestao-reviews' => 'gbp',
      'otimizacao-gbp' => 'gbp',
      'prova-social' => 'general',
      'mercado-maduro' => 'general',
      'presenca-digital' => 'general'
    )
  end

  it 'aceita a jogada só no modo dela' do
    expect(described_class.valid_for_mode?('prova-social', 'general')).to be(true)
    expect(described_class.valid_for_mode?('prova-social', 'gbp')).to be(false)
    expect(described_class.valid_for_mode?('inexistente', 'gbp')).to be(false)
  end
end
