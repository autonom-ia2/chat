require 'rails_helper'

# Motor da nota por conta (#681): legado até o superadmin virar a conta para o Orth.
RSpec.describe Autonomia::Prospecting::Setting do
  let(:setting) { described_class.for_account(create(:account)) }
  let(:weight_mapping) { Autonomia::Prospecting::Scoring::WeightMapping }

  describe '#score_engine' do
    it 'é o legado quando ninguém virou a conta' do
      expect(setting.score_engine).to eq('legacy')
      expect(setting).not_to be_orth_score_engine
    end

    it 'guarda a virada no metadata sem mexer no resto dele' do
      setting.update!(search_country: 'PT', search_score_mode: 'general')

      setting.update!(score_engine: 'orth')

      expect(setting.reload.score_engine).to eq('orth')
      expect(setting).to be_orth_score_engine
      expect(setting.metadata).to include('score_engine' => 'orth', 'search_country' => 'PT', 'search_score_mode' => 'general')
    end

    it 'recusa motor fora da lista' do
      setting.score_engine = 'outro'

      expect(setting).not_to be_valid
      expect(setting.errors[:metadata]).to include('score_engine must be legacy or orth')
    end
  end

  describe '#orth_scoring_weights' do
    it 'é nil (padrão do Orth) no perfil padrão' do
      expect(setting.orth_scoring_weights).to be_nil
    end

    it 'mapeia os pesos próprios da conta' do
      setting.update!(scoring_mode: 'custom', custom_scoring_weights: { 'website' => 50 })
      allow(weight_mapping).to receive(:from_legacy).with(setting.active_scoring_weights).and_return('website' => 60)

      expect(setting.orth_scoring_weights).to eq('website' => 60)
    end

    it 'mapeia os pesos próprios mesmo quando a conta guardou os mesmos números do padrão' do
      setting.update!(scoring_mode: 'custom', custom_scoring_weights: Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS)
      allow(weight_mapping).to receive(:from_legacy).and_return('website' => 30)

      expect(setting.orth_scoring_weights).to eq('website' => 30)
    end

    it 'mapeia o perfil do catálogo que não é o padrão' do
      profile = Autonomia::Prospecting::ScoringProfile.create!(name: 'Vender site', weights: { 'website' => 70 })
      setting.update!(scoring_profile: profile)
      allow(weight_mapping).to receive(:from_legacy).with(profile.weights_with_defaults).and_return('website' => 80)

      expect(setting.orth_scoring_weights).to eq('website' => 80)
    end
  end
end
