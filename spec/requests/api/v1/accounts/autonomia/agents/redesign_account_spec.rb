require 'rails_helper'

RSpec.describe 'Agentes redesign account gate', type: :request do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_agents_redesign' => true })
  end
  let(:administrator) { create(:user, account: account, role: :administrator) }

  it 'exposes separate boolean gates and defaults off without an account opt-in' do
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_AGENTS_REDESIGN: 'true' do
      get "/api/v1/accounts/#{account.id}", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('autonomia_agents_enabled' => true, 'autonomia_agents_redesign_enabled' => true)
      expect(response.parsed_body.fetch('autonomia_copilot_available')).to be_in([true, false])

      account.update!(internal_attributes: { 'autonomia_agents_enabled' => true })
      get "/api/v1/accounts/#{account.id}", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('autonomia_agents_enabled' => true, 'autonomia_agents_redesign_enabled' => false)
    end
  end

  it 'keeps the existing product available when the redesign master is off' do
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_AGENTS_REDESIGN: 'false' do
      get "/api/v1/accounts/#{account.id}", headers: administrator.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('autonomia_agents_enabled' => true, 'autonomia_agents_redesign_enabled' => false)
    end
  end
end
