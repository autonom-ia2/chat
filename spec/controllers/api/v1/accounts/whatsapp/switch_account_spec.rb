require 'rails_helper'

# chat#1217 — "Trocar de conta" usa POST /whatsapp/authorization com inbox_id, inclusive em caixa
# configurada à mão (sem source) que está funcionando.
RSpec.describe 'WhatsApp switch account API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    ch = build(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511978622068',
                                  provider_config: { 'api_key' => 'old', 'phone_number_id' => 'old_phone', 'business_account_id' => 'old_waba' })
    allow(ch).to receive(:validate_provider_config).and_return(true)
    allow(ch).to receive(:sync_templates)
    allow(ch).to receive(:setup_webhooks)
    ch.save!
    ch
  end
  let!(:inbox) { create(:inbox, channel: channel, account: account) }
  let(:params) { { code: 'code', waba_id: 'new_waba', phone_number_id: 'new_phone', inbox_id: inbox.id } }
  let(:embedded_signup) { instance_double(Whatsapp::EmbeddedSignupService) }

  before { allow(Whatsapp::EmbeddedSignupService).to receive(:new).and_return(embedded_signup) }

  def switch_account
    post "/api/v1/accounts/#{account.id}/whatsapp/authorization", params: params, headers: administrator.create_new_auth_token, as: :json
  end

  it 'accepts a healthy legacy inbox and reports it ready to receive' do
    allow(embedded_signup).to receive(:perform).and_return(channel)

    switch_account

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('success' => true, 'id' => inbox.id, 'ready_to_receive' => true)
  end

  it 'reports when the webhook subscription did not stick' do
    allow(embedded_signup).to receive(:perform) do
      channel.prompt_reauthorization!
      channel
    end

    switch_account

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['ready_to_receive']).to be(false)
  end

  it 'returns a stable code when Meta returns another number' do
    error = Whatsapp::SwitchAccount::PhoneNumberMismatchError.new(expected: '+5511978622068', received: '+5511944547873')
    allow(embedded_signup).to receive(:perform).and_raise(error)

    switch_account

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include(
      'success' => false,
      'error_code' => 'phone_number_mismatch',
      'expected_phone_number' => '+5511978622068',
      'received_phone_number' => '+5511944547873'
    )
  end

  it 'keeps the generic error shape for other failures' do
    allow(embedded_signup).to receive(:perform).and_raise(StandardError, 'Token exchange failed')

    switch_account

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('success' => false, 'error' => 'Token exchange failed')
  end

  it 'refuses an agent without inbox management' do
    agent = create(:user, account: account, role: :agent)

    post "/api/v1/accounts/#{account.id}/whatsapp/authorization", params: params, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Whatsapp::EmbeddedSignupService).not_to have_received(:new)
  end

  it 'does not reach an inbox from another account' do
    other_inbox = create(:inbox, account: create(:account))

    post "/api/v1/accounts/#{account.id}/whatsapp/authorization", params: params.merge(inbox_id: other_inbox.id),
                                                                  headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(Whatsapp::EmbeddedSignupService).not_to have_received(:new)
  end

  it 'keeps the new inbox response unchanged' do
    allow(embedded_signup).to receive(:perform).and_return(channel)

    post "/api/v1/accounts/#{account.id}/whatsapp/authorization", params: params.except(:inbox_id),
                                                                  headers: administrator.create_new_auth_token, as: :json

    expect(response.parsed_body).not_to have_key('ready_to_receive')
  end
end
