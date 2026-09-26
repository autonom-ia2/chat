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

  # Jogada salva (#732): vale na conta e no modo dela; as prontas continuam valendo em qualquer conta.
  it 'aceita a jogada salva só na conta e no modo dela' do
    account = create(:account)
    saved = Autonomia::Prospecting::SavedPreset.create!(account: account, name: 'Sem site', score_mode: 'general',
                                                        filters: { 'has_website' => 'no' })

    expect(described_class.valid_for?(account: account, preset_id: saved.preset_id, score_mode: 'general')).to be(true)
    expect(described_class.valid_for?(account: account, preset_id: saved.preset_id, score_mode: 'gbp')).to be(false)
    expect(described_class.valid_for?(account: create(:account), preset_id: saved.preset_id, score_mode: 'general')).to be(false)
    expect(described_class.valid_for?(account: account, preset_id: 'prova-social', score_mode: 'general')).to be(true)
    expect(described_class.valid_for?(account: account, preset_id: 'inexistente', score_mode: 'general')).to be(false)
  end
end
