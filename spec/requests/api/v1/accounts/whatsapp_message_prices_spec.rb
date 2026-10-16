require 'rails_helper'

# Preço por envio e franquia do mês na tela de Modelos e na revisão da campanha (#1332).
RSpec.describe 'WhatsApp message prices API (#1332)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:path) { "/api/v1/accounts/#{account.id}/whatsapp_message_prices" }

  it 'gives the price table and how many free replies each number used this month' do
    conversation = create(:conversation, account: account, inbox: channel.inbox)
    create(:message, account: account, inbox: channel.inbox, conversation: conversation, message_type: :outgoing)
    stub_request(:get, "https://graph.facebook.com/#{Whatsapp::Templates::MetaClient.api_version}/123456789")
      .with(query: { fields: 'timezone_id' }).to_return(status: 200, body: { timezone_id: '25' }.to_json,
                                                        headers: { 'Content-Type' => 'application/json' })

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload).to include('country' => 'BR', 'currency' => 'BRL', 'effective_from' => '2026-10-01')
    expect(payload['prices']).to eq('marketing' => '0.3217', 'utility' => '0.035', 'authentication' => '0.035', 'service' => '0.035')
    expect(payload['free_tier']).to eq('service' => { 'messages' => 1000, 'period' => 'month', 'per' => 'phone_number' })
    expect(payload['service_usage']).to eq([{ 'inbox_id' => channel.inbox.id, 'name' => channel.inbox.name, 'messages' => 1 }])
  end

  it 'refuses an agent without a role (OSS: administrators only)' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
