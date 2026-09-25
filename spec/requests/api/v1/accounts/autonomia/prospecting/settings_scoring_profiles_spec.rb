require 'rails_helper'

# Aba Score da configuração (#681, E5 frente C): perfis restritos a contas e a leitura da nota do Orth.
RSpec.describe 'Autonomia prospecting settings: perfis de nota', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/settings" }
  let(:profile_class) { Autonomia::Prospecting::ScoringProfile }
  let!(:default_profile) { profile_class.default_profile }
  let!(:global_profile) { profile_class.create!(name: 'Global') }
  let!(:own_profile) { profile_class.create!(name: 'Exclusivo da conta', account_ids: [account.id]) }
  let!(:foreign_profile) { profile_class.create!(name: 'Exclusivo de outra', account_ids: [other_account.id]) }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'lista de perfis' do
    it 'traz os globais e os restritos da conta, sem o de outra conta e sem id de conta nenhuma' do
      get settings_url, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(payload['scoring_profiles'].pluck('name')).to contain_exactly('Padrão', 'Global', 'Exclusivo da conta')
      expect(payload['scoring_profiles'].find { |p| p['name'] == 'Exclusivo da conta' }['restricted']).to be(true)
      expect(payload['scoring_profiles'].find { |p| p['name'] == 'Global' }['restricted']).to be(false)
      expect(response.body).not_to include('Exclusivo de outra')
      expect(payload['scoring_profiles'].flat_map(&:keys).uniq).to contain_exactly('id', 'name', 'default', 'weights', 'restricted')
    end

    it 'mantém o perfil global disponível para qualquer conta' do
      other_admin = create(:user, :administrator, account: other_account)
      Autonomia::Prospecting::Config.enable_for!(other_account)

      get "/api/v1/accounts/#{other_account.id}/autonomia/prospecting/settings", headers: auth_headers(other_admin)

      expect(payload['scoring_profiles'].pluck('name')).to contain_exactly('Padrão', 'Global', 'Exclusivo de outra')
    end
  end

  describe 'escolha de perfil' do
    it 'recusa com 422 o perfil restrito de outra conta e não muda a configuração' do
      patch settings_url, params: { settings: { scoring_mode: 'profile', scoring_profile_id: foreign_profile.id } },
                          headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.errors.scoring_profile_unavailable'))
      expect(Autonomia::Prospecting::Setting.for_account(account).reload.scoring_profile_id).to eq(default_profile.id)
    end

    it 'aceita o perfil restrito da própria conta e o global' do
      patch settings_url, params: { settings: { scoring_mode: 'profile', scoring_profile_id: own_profile.id } },
                          headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(payload['scoring_profile_id']).to eq(own_profile.id)

      patch settings_url, params: { settings: { scoring_mode: 'profile', scoring_profile_id: global_profile.id } },
                          headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(payload['scoring_profile_id']).to eq(global_profile.id)
    end

    it 'mostra o perfil padrão quando o perfil salvo deixou de valer para a conta' do
      Autonomia::Prospecting::Setting.for_account(account).update!(scoring_profile: global_profile)
      global_profile.update!(account_ids: [other_account.id])

      get settings_url, headers: auth_headers(admin)

      expect(payload['scoring_profile_id']).to eq(default_profile.id)
      expect(payload['active_scoring_weights']).to eq(default_profile.weights_with_defaults)
    end
  end

  describe 'motor de nota' do
    # Conta não virada: a configuração responde exatamente o que respondia antes da E5, mais o nome do motor.
    it 'responde legacy sem pesos do Orth para a conta não virada' do
      get settings_url, headers: auth_headers(admin)

      expect(payload['score_engine']).to eq('legacy')
      expect(payload).not_to have_key('orth_scoring_weights')
      expect(payload['scoring_profiles'].first).not_to have_key('orth_weights')
      expect(payload['active_scoring_weights']).to eq(Autonomia::Prospecting::ScoringProfile::DEFAULT_WEIGHTS)
    end

    context 'with a conta virada para o Orth' do
      # Padrão do Orth: site 30, telefone 10, rating 20, volume 15, atividade 10, fotos 15.
      let(:orth_default) { { 'website' => 30, 'phone' => 10, 'rating' => 20, 'volume' => 15, 'activity' => 10, 'photos' => 15 } }
      let(:weight_mapping) { Autonomia::Prospecting::Scoring::WeightMapping }

      before do
        Autonomia::Prospecting::Setting.for_account(account).update!(score_engine: 'orth')
      end

      it 'usa os pesos padrão do Orth quando a conta está no perfil padrão' do
        get settings_url, headers: auth_headers(admin)

        expect(payload['score_engine']).to eq('orth')
        expect(payload['orth_scoring_weights']).to eq(orth_default)
        expect(payload['scoring_profiles'].find { |p| p['default'] }['orth_weights']).to eq(orth_default)
      end

      it 'converte o perfil escolhido e os pesos próprios da conta para os 6 componentes' do
        custom = { 'website' => 40, 'phone' => 10, 'rating' => 20, 'reviews_count' => 10, 'activity' => 10, 'photos' => 10,
                   'google_rank' => 0, 'query_relevance' => 0 }
        setting = Autonomia::Prospecting::Setting.for_account(account)
        setting.update!(scoring_mode: 'custom', scoring_profile: nil, custom_scoring_weights: custom)

        get settings_url, headers: auth_headers(admin)

        expect(payload['orth_scoring_weights']).to eq(weight_mapping.from_legacy(custom))
        global_entry = payload['scoring_profiles'].find { |p| p['name'] == 'Global' }
        expect(global_entry['orth_weights']).to eq(weight_mapping.from_legacy(global_profile.weights_with_defaults))
      end
    end
  end
end
