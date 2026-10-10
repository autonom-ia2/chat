require 'rails_helper'

RSpec.describe 'Brand kit permissions', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: permissions) }
  let(:headers) { user.create_new_auth_token }
  let(:kits_path) { "/api/v1/accounts/#{account.id}/brand_kits" }
  let(:imports_path) { "/api/v1/accounts/#{account.id}/brand_kit_imports" }
  let!(:kit) { create(:brand_kit, account: account) }
  let(:import) { create(:brand_import_job, account: account, status: :succeeded, result: {}) }
  let(:params) { { brand_kit: { name: 'Nova', appearance: attributes_for(:brand_kit)[:appearance] } } }

  before { user.account_users.find_by!(account: account).update!(custom_role: role) }

  context 'with campaign_view only' do
    let(:permissions) { ['campaign_view'] }

    it 'reads kits and imports but changes nothing' do
      get kits_path, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      get "#{kits_path}/#{kit.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      get "#{imports_path}/#{import.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      post kits_path, params: params, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      patch "#{kits_path}/#{kit.id}", params: params, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{kits_path}/#{kit.id}/set_default", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{kits_path}/#{kit.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      post imports_path, params: { url: 'https://hub2you.ai' }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      expect(BrandKit.count).to eq(1)
      expect(kit.reload.archived_at).to be_nil
    end
  end

  context 'with campaign_manage' do
    let(:permissions) { ['campaign_manage'] }

    it 'creates, edits, archives and imports' do
      post kits_path, params: params, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      patch "#{kits_path}/#{kit.id}", params: { brand_kit: { name: 'Editada' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      delete "#{kits_path}/#{kit.id}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post imports_path, params: { url: 'https://hub2you.ai' }, headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
    end
  end

  context 'with an unrelated permission' do
    let(:permissions) { ['conversation_manage'] }

    it 'cannot even read' do
      get kits_path, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
