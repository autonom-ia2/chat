require 'rails_helper'

# End-to-end gates for the module keys added to custom roles in #452.
RSpec.describe 'Custom role module access', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  describe 'Autonom.ia agents' do
    around do |example|
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
    end

    let(:agents_path) { "/api/v1/accounts/#{account.id}/autonomia/agents" }

    it 'lets autonomia_view list agents but not create them' do
      headers = custom_role_user('autonomia_view').create_new_auth_token

      get agents_path, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      post agents_path, params: { name: 'Novo' }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps plain agents out' do
      get agents_path, headers: create(:user, account: account, role: :agent).create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'inbox settings' do
    let!(:inbox) { create(:inbox, account: account) }

    it 'lists every account inbox to inbox_view and blocks updates' do
      headers = custom_role_user('inbox_view').create_new_auth_token

      get "/api/v1/accounts/#{account.id}/inboxes", headers: headers, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to include(inbox.id)

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", params: { name: 'Outro' }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets inbox_manage update an inbox it is not a member of' do
      headers = custom_role_user('inbox_manage').create_new_auth_token

      patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", params: { name: 'Outro' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(inbox.reload.name).to eq('Outro')
    end
  end

  describe 'canned responses' do
    let(:path) { "/api/v1/accounts/#{account.id}/canned_responses" }
    let(:params) { { canned_response: { short_code: 'oi', content: 'Olá' } } }

    it 'blocks custom roles without canned_response_manage' do
      post path, params: params, headers: custom_role_user('contact_manage').create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps plain agents creating canned responses' do
      post path, params: params, headers: create(:user, account: account, role: :agent).create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
