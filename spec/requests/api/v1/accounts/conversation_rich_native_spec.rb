require 'rails_helper'

# chat#1709: a conversa diz à tela do "+" quais formatos saem nativos agora (`whatsapp_api_rich_native`).
RSpec.describe 'Conversation whatsapp_api_rich_native', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

  before do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
    Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(inbox.id))
  end

  def rich_native
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body['whatsapp_api_rich_native']
  end

  it 'lists the native types next to whatsapp_api_reply when the flag is on' do
    account.enable_features!('whatsapp_rich_native')

    expect(rich_native).to eq(%w[options location contact poll])
    expect(response.parsed_body['whatsapp_api_reply']).to be(true)
  end

  it 'is an empty list with the flag off' do
    expect(rich_native).to eq([])
  end
end
