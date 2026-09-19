require 'rails_helper'

RSpec.describe 'WAHA inboxes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_api, account: account,
                         additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-teste' })
  end
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Waha::Client) }

  before { allow(Waha::Client).to receive(:new).and_return(client) }

  describe 'POST /api/v1/accounts/{account.id}/waha_inboxes/{inbox_id}/reconnect' do
    let(:path) { "/api/v1/accounts/#{account.id}/waha_inboxes/#{inbox.id}/reconnect" }

    it 'logs out and lets the running session start pairing again' do
      allow(client).to receive(:logout_session).with('sessao-teste')
      allow(client).to receive(:get_session).with('sessao-teste').and_return({ 'status' => 'STARTING' })
      allow(client).to receive(:start_session)

      post path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(client).not_to have_received(:start_session)
    end

    it 'starts a stopped session, which logout alone does not restart' do
      allow(client).to receive(:logout_session).with('sessao-teste')
      allow(client).to receive(:get_session).with('sessao-teste').and_return({ 'status' => 'STOPPED' })
      allow(client).to receive(:start_session).with('sessao-teste')

      post path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(client).to have_received(:start_session).with('sessao-teste')
    end

    it 'restarts the session when logout fails' do
      allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'boom')
      allow(client).to receive(:restart_session).with('sessao-teste')
      allow(client).to receive(:get_session).and_return({ 'status' => 'STARTING' })

      post path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(client).to have_received(:restart_session).with('sessao-teste')
    end

    it 'does not create another inbox' do
      allow(client).to receive(:logout_session)
      allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
      allow(client).to receive(:start_session)
      inbox

      expect do
        post path, headers: admin.create_new_auth_token, as: :json
      end.not_to change(Inbox, :count)
    end

    it 'is not available to agents' do
      agent = create(:user, account: account, role: :agent)

      post path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
