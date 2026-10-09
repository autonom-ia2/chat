require 'rails_helper'

RSpec.describe 'Super Admin Agentes redesign opt-in', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'preserve' => 'value' }) }
  let(:url) { "/super_admin/accounts/#{account.id}/toggle_agents_redesign" }

  it 'allows only the authenticated platform administrator to toggle the new account gate' do
    super_admin = create(:super_admin)
    sign_in(super_admin, scope: :super_admin)

    post url, params: { enabled: 'true' }
    expect(response).to have_http_status(:found)
    expect(account.reload.internal_attributes).to include(
      'autonomia_agents_redesign' => true, 'autonomia_agents_enabled' => true, 'preserve' => 'value'
    )

    post url, params: { enabled: 'false' }
    expect(response).to have_http_status(:found)
    expect(account.reload.internal_attributes).to include('autonomia_agents_redesign' => false, 'autonomia_agents_enabled' => true)
  end

  it 'rejects a dashboard account administrator without changing the account' do
    administrator = create(:user, account: account, role: :administrator)
    post url, params: { enabled: true }, headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.internal_attributes).not_to have_key('autonomia_agents_redesign')
  end

  it 'rejects an invalid flag value instead of converting arbitrary text to true' do
    super_admin = create(:super_admin)
    sign_in(super_admin, scope: :super_admin)

    post url, params: { enabled: 'invalid' }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.internal_attributes).not_to have_key('autonomia_agents_redesign')
  end

  it 'redirects an unauthenticated HTML request without changing the account' do
    post url, params: { enabled: 'true' }

    expect(response).to redirect_to('/super_admin/sign_in')
    expect(account.reload.internal_attributes).not_to have_key('autonomia_agents_redesign')
  end
end
