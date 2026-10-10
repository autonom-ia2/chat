require 'rails_helper'

# #1181 — as leituras da nova jornada de Agentes (L1 e L2) seguem a chave autonomia_view das funções personalizadas.
RSpec.describe 'Autonomia agents journey reads with custom roles', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:paths) do
    %w[numeros_da_semana canais_ocupados].map { |leitura| "/api/v1/accounts/#{account.id}/autonomia/#{leitura}" }
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before { account.enable_features!('autonomia_agents_journey') }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  it 'lets autonomia_view read both' do
    headers = custom_role_user('autonomia_view').create_new_auth_token

    paths.each do |path|
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:success), path
    end
  end

  it 'keeps agents without a role out of both' do
    headers = create(:user, account: account, role: :agent).create_new_auth_token

    paths.each do |path|
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized), path
    end
  end
end
