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

  describe 'POST /api/v1/accounts/{account.id}/waha_inboxes' do
    let(:path) { "/api/v1/accounts/#{account.id}/waha_inboxes" }
    let(:provisioner) { instance_double(Waha::InboxProvisioner) }

    before { allow(Waha::InboxProvisioner).to receive(:new).and_return(provisioner) }

    locales = %w[en pt_BR]
    %w[invalid_phone integration_not_configured account_token_missing remote_setup_failed].each do |code|
      locales.each do |locale|
        it "preserves the legacy #{code} while adding a stable code and #{locale} message" do
          account.update!(locale: locale)
          allow(provisioner).to receive(:perform).and_raise(Waha::InboxProvisioner::Error, code)

          post path, params: { phone: '5511999999999' }, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body).to include('error' => code, 'code' => code)
          expect(response.parsed_body['message']).to eq(I18n.t("autonomia.agents.errors.#{code}", locale: locale))
          expect(response.parsed_body['message'].downcase).not_to include('translation missing')
        end
      end
    end

    it 'does not expose an unrecognized provider error to the client' do
      allow(provisioner).to receive(:perform).and_raise(Waha::InboxProvisioner::Error, 'raw provider detail')

      post path, params: { phone: '5511999999999' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'remote_setup_failed', 'code' => 'remote_setup_failed')
      expect(response.body).not_to include('raw provider detail')
    end
  end

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

    it 'returns the stable reconnect code without leaking provider details' do
      allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'raw provider detail')
      allow(client).to receive(:restart_session).and_raise(Waha::Client::Error, 'raw provider detail')
      allow(Rails.logger).to receive(:error)

      post path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'reconnect_failed', 'code' => 'reconnect_failed')
      expect(response.body).not_to include('raw provider detail')
      expect(Rails.logger).not_to have_received(:error).with(include('raw provider detail'))
    end

    it 'returns the stable code for an inbox from another provider' do
      channel.update!(additional_attributes: {})

      post path, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'not_a_waha_inbox', 'code' => 'not_a_waha_inbox')
    end
  end
end
