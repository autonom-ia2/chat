require 'rails_helper'

# Perfil restrito na busca (#681, E5 frente C): a busca só pontua com perfil que vale para a conta.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:setting) { Autonomia::Prospecting::Setting.for_account(account) }
  let!(:default_profile) { Autonomia::Prospecting::ScoringProfile.default_profile }
  let(:heavy_website) { Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS.merge('website' => 95) }

  before { setting.update!(provider: 'mock') }

  def run_search
    described_class.new(account: account, user: user, params: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 1 })
                   .perform
  end

  def weights_used
    used = []
    allow(Autonomia::Prospecting::LeadScorer).to receive(:new).and_wrap_original do |original, **kwargs|
      used << kwargs[:weights]
      original.call(**kwargs)
    end
    run_search
    used.uniq
  end

  it 'pontua com o perfil restrito da própria conta' do
    own = Autonomia::Prospecting::ScoringProfile.create!(name: 'Exclusivo', weights: heavy_website, account_ids: [account.id])
    setting.update!(scoring_profile: own)

    expect(weights_used).to eq([own.weights_with_defaults])
  end

  it 'pontua com o perfil global para qualquer conta' do
    global = Autonomia::Prospecting::ScoringProfile.create!(name: 'Global', weights: heavy_website)
    setting.update!(scoring_profile: global)

    expect(weights_used).to eq([global.weights_with_defaults])
  end

  # O superadmin restringiu o perfil a outra conta depois que esta já o usava.
  it 'não pontua com perfil restrito a outra conta e cai no padrão' do
    profile = Autonomia::Prospecting::ScoringProfile.create!(name: 'Era global', weights: heavy_website)
    setting.update!(scoring_profile: profile)
    profile.update!(account_ids: [other_account.id])

    expect(weights_used).to eq([default_profile.weights_with_defaults])
  end
end
