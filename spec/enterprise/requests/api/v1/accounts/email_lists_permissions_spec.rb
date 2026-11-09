require 'rails_helper'

# G52 (#2760): na função personalizada, campaign_view vê as listas e campaign_manage cria, renomeia e apaga.
RSpec.describe 'Email list permissions', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: permissions) }
  let(:headers) { user.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/lists" }
  let(:lista) { EmailList.criar(account: account, name: 'Dicas do mês') }

  before { user.account_users.find_by!(account: account).update!(custom_role: role) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true') { example.run }
  end

  context 'with campaign_view only' do
    let(:permissions) { ['campaign_view'] }

    it 'vê as listas, mas não cria, renomeia nem apaga' do
      lista
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post path, params: { email_list: { name: 'Nova' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      patch "#{path}/#{lista.id}", params: { email_list: { name: 'X' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{path}/#{lista.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with campaign_manage' do
    let(:permissions) { ['campaign_manage'] }

    it 'cria a lista' do
      post path, params: { email_list: { name: 'Nova' } }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
    end
  end
end
