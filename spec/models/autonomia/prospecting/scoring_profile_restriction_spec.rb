require 'rails_helper'

# Perfil de nota restrito a contas (#681, E5 frente C). Sem conta vinculada o perfil é global, como sempre foi; com
# contas vinculadas ele só aparece e só vale para elas. O perfil de uma conta não pode vazar para outra.
RSpec.describe Autonomia::Prospecting::ScoringProfile do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:default_profile) { described_class.default_profile }
  let!(:global_profile) { described_class.create!(name: 'Global') }
  let!(:own_profile) { described_class.create!(name: 'Da conta', account_ids: [account.id]) }
  let!(:foreign_profile) { described_class.create!(name: 'De outra conta', account_ids: [other_account.id]) }

  describe '.available_to' do
    it 'lista os globais e os restritos da própria conta, nunca os de outra' do
      expect(described_class.available_to(account)).to contain_exactly(default_profile, global_profile, own_profile)
      expect(described_class.available_to(other_account)).to contain_exactly(default_profile, global_profile, foreign_profile)
    end

    it 'não repete o perfil vinculado a várias contas' do
      shared = described_class.create!(name: 'Compartilhado', account_ids: [account.id, other_account.id])

      expect(described_class.available_to(account).where(id: shared.id).count).to eq(1)
      expect(described_class.available_to(account).to_a.count(shared)).to eq(1)
    end
  end

  describe '#available_to?' do
    it 'vale para qualquer conta quando é global e só para as vinculadas quando é restrito' do
      expect(global_profile.available_to?(other_account)).to be(true)
      expect(own_profile.available_to?(account)).to be(true)
      expect(own_profile.available_to?(other_account)).to be(false)
      expect(own_profile).to be_restricted
      expect(global_profile).not_to be_restricted
    end
  end

  it 'recusa restringir o perfil padrão, que é o que vale para toda conta sem escolha' do
    default_profile.account_ids = [account.id]

    expect(default_profile).not_to be_valid
    expect(default_profile.errors[:base]).to include(I18n.t('autonomia.prospecting.errors.default_scoring_profile_restricted'))
  end

  it 'apaga o vínculo junto com o perfil, sem apagar a conta' do
    expect { own_profile.destroy! }.to change(Autonomia::Prospecting::ScoringProfileAccount, :count).by(-1)
    expect(account.reload).to be_present
  end

  describe 'uso pela configuração da conta' do
    let(:setting) { Autonomia::Prospecting::Setting.for_account(account) }

    it 'aceita o perfil restrito da própria conta e usa os pesos dele' do
      own_profile.update!(weights: own_profile.weights_with_defaults.merge('website' => 90))

      setting.update!(scoring_mode: 'profile', scoring_profile: own_profile)

      expect(setting.active_scoring_profile).to eq(own_profile)
      expect(setting.active_scoring_weights['website']).to eq(90)
    end

    it 'recusa o perfil restrito de outra conta' do
      setting.scoring_profile = foreign_profile

      expect(setting).not_to be_valid
      expect(setting.errors[:base]).to include(I18n.t('autonomia.prospecting.errors.scoring_profile_unavailable'))
    end

    # O superadmin pode restringir depois o perfil que a conta já usava. A conta cai no padrão em vez de seguir
    # nos pesos de um perfil que deixou de ser dela, e continua salvando o resto da configuração.
    it 'cai no perfil padrão quando o perfil escolhido deixa de valer para a conta' do
      global_profile.update!(weights: global_profile.weights_with_defaults.merge('website' => 77))
      setting.update!(scoring_mode: 'profile', scoring_profile: global_profile)

      global_profile.update!(account_ids: [other_account.id])
      setting.reload

      expect(setting.active_scoring_profile).to eq(default_profile)
      expect(setting.active_scoring_weights).to eq(default_profile.weights_with_defaults)
      expect(setting.update(cache_ttl_seconds: 60)).to be(true)
    end
  end
end
