require 'rails_helper'

describe WhatsappHybrid::CloudFailureFallback do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, account: inbox.account) }
  let(:client) { instance_double(Waha::Client) }
  let(:message) do
    create(:message, message_type: :outgoing, content: 'retorno', conversation: conversation, account: inbox.account,
                     inbox: inbox, source_id: 'wamid.cloud-1', sender: create(:user, account: inbox.account))
  end

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

  before do
    WhatsappHybrid::Connection.create!(account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0FALL', send_text: {}, start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
  end

  def status_webhook(code)
    {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages', value: { statuses: [{
        id: message.source_id, status: 'failed', recipient_id: '5511937016094', timestamp: Time.current.to_i.to_s,
        errors: [{ code: code, title: 'Re-engagement message' }]
      }] } }] }]
    }.with_indifferent_access
  end

  it 'resends through WhatsApp API when Meta says the 24h window was closed' do
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: status_webhook(131_047)).perform

    expect(client).to have_received(:send_text).with(session: 'hybrid-test', chat_id: '5511937016094@c.us', text: 'retorno', id: '3EB0FALL')
    expect(message.reload.status).not_to eq('failed')
    expect(message.content_attributes).to include('whatsapp_transport' => 'web', 'whatsapp_transport_fallback' => true)
  end

  it 'restores the original failure when the resend breaks outside the engine' do
    allow(client).to receive(:new_message_id).and_raise(Redis::CannotConnectError)

    expect do
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: status_webhook(131_047)).perform
    end.to raise_error(Redis::CannotConnectError)

    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to be_present
  end

  it 'never resends on other failures' do
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: status_webhook(131_026)).perform

    expect(client).not_to have_received(:send_text)
    expect(message.reload.status).to eq('failed')
  end
end
