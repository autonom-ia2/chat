require 'rails_helper'

# Catálogo de perfis de nota no superadmin (#681, E5 frente C): perfil global por padrão, com a opção
# "restrito a estas contas".
RSpec.describe 'Super Admin prospecting scoring profiles', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:prospecting_account) { create(:account, name: 'Conta com prospecção') }
  let!(:other_prospecting_account) { create(:account, name: 'Outra com prospecção') }
  let!(:plain_account) { create(:account, name: 'Conta sem prospecção') }
  let(:profile_class) { Autonomia::Prospecting::ScoringProfile }
  let(:base_path) { '/super_admin/prospecting_scoring_profiles' }

  before do
    Autonomia::Prospecting::Config.enable_for!(prospecting_account)
    Autonomia::Prospecting::Config.enable_for!(other_prospecting_account)
    profile_class.default_profile
    sign_in(super_admin, scope: :super_admin)
  end

  def profile_params(name:, account_ids: nil, default: '0')
    params = { name: name, default: default, weights: profile_class::DEFAULT_WEIGHTS }
    params[:account_ids] = account_ids unless account_ids.nil?
    { autonomia_prospecting_scoring_profile: params }
  end

  it 'oferece no formulário só as contas com prospecção' do
    get "#{base_path}/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Conta com prospecção', 'Outra com prospecção')
    expect(response.body).not_to include('Conta sem prospecção')
    expect(response.body).not_to include('<select')
  end

  it 'cria perfil global quando nenhuma conta é marcada' do
    post base_path, params: profile_params(name: 'Global', account_ids: [''])

    expect(response).to redirect_to(base_path)
    expect(profile_class.find_by!(name: 'Global')).not_to be_restricted
  end

  it 'cria perfil restrito às contas marcadas e mostra a restrição na lista' do
    post base_path, params: profile_params(name: 'Restrito', account_ids: ['', prospecting_account.id.to_s])

    profile = profile_class.find_by!(name: 'Restrito')
    expect(profile.account_ids).to eq([prospecting_account.id])

    get base_path
    expect(response.body).to include('Restricted to: Conta com prospecção')
    expect(response.body).to include('Global')
  end

  it 'volta o perfil a global ao desmarcar todas as contas' do
    profile = profile_class.create!(name: 'Restrito', account_ids: [prospecting_account.id])

    patch "#{base_path}/#{profile.id}", params: profile_params(name: 'Restrito', account_ids: [''])

    expect(response).to redirect_to(base_path)
    expect(profile.reload).not_to be_restricted
  end

  it 'mantém a restrição quando o formulário não fala de contas' do
    profile = profile_class.create!(name: 'Restrito', account_ids: [prospecting_account.id])

    patch "#{base_path}/#{profile.id}", params: profile_params(name: 'Renomeado')

    expect(profile.reload.name).to eq('Renomeado')
    expect(profile.account_ids).to eq([prospecting_account.id])
  end

  it 'mostra a conta já vinculada mesmo que a prospecção dela tenha sido desligada' do
    profile = profile_class.create!(name: 'Restrito', account_ids: [plain_account.id])

    get "#{base_path}/#{profile.id}/edit"

    expect(response.body).to include('Conta sem prospecção')
  end

  it 'recusa restringir o perfil padrão e explica no formulário' do
    default_profile = profile_class.default_profile

    patch "#{base_path}/#{default_profile.id}",
          params: profile_params(name: 'Padrão', default: '1', account_ids: [prospecting_account.id.to_s])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(CGI.escapeHTML(I18n.t('autonomia.prospecting.errors.default_scoring_profile_restricted')))
    expect(default_profile.reload).not_to be_restricted
  end
end
