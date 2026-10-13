require 'rails_helper'

# chat#1473: o plano B do WhatsApp Híbrido (erro 131047 da Meta) reenvia pelo WhatsApp API em TEXTO. Um tipo sem
# versão em texto não pode ser reenviado só com o corpo. Router e CloudFailureFallback reais; dublê só no motor.
describe 'Rich messages and the WhatsApp Híbrido fallback' do # rubocop:disable RSpec/DescribeClass
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, account: inbox.account) }
  let(:client) { instance_double(Waha::Client) }
  let(:mute_type) do
    Class.new do
      def initialize(_payload); end
      def error_for(_body); end
      def whatsapp_cloud_payload(_body) = { type: 'spec_mute', spec_mute: {} }
      def self.text_version? = false
      def fallback_text(_body) = ''
    end
  end

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

  before do
    stub_const('RichMessages::Types::SpecMute', mute_type)
    WhatsappHybrid::Connection.create!(account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0FALL', send_text: {}, start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
  end

  # A mensagem como fica depois de aceita pela Meta: enviada, com o id dela.
  def accepted_by_meta(content_attributes)
    create(:message, message_type: :outgoing, content: 'retorno', conversation: conversation, account: inbox.account, inbox: inbox,
                     source_id: 'wamid.cloud-1', sender: create(:user, account: inbox.account), content_attributes: content_attributes)
  end

  def window_closed_status(message)
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages', value: { statuses: [{
        id: message.source_id, status: 'failed', recipient_id: '5511937016094', timestamp: Time.current.to_i.to_s,
        errors: [{ code: 131_047, title: 'Re-engagement message' }]
      }] } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
    message.reload
  end

  it 'does not resend a type without a text version: the message stays failed with the error from Meta' do
    message = window_closed_status(accepted_by_meta(rich_message: { type: 'spec_mute' }))

    expect(client).not_to have_received(:send_text)
    expect(message.status).to eq('failed')
    expect(message.external_error).to include('131047')
    expect(message.content_attributes.keys).not_to include('whatsapp_transport', 'whatsapp_transport_fallback')
  end

  it 'does not let the router send by text a type that does not exist' do
    message = accepted_by_meta(rich_message: { type: 'carousel' })

    expect(WhatsappHybrid::Router.new(conversation).web_allowed_for?(message)).to be(false)
    expect(WhatsappHybrid::Router.new(conversation).web_allowed_for?(accepted_by_meta({}))).to be(true)
  end

  it 'resends a link button as body, label and link' do
    message = window_closed_status(accepted_by_meta(rich_message: { type: 'link_button', label: 'Abrir', url: 'https://exemplo.com.br/x' }))

    expect(client).to have_received(:send_text).with(session: 'hybrid-test', chat_id: '5511937016094@c.us',
                                                     text: "retorno\n\nAbrir: https://exemplo.com.br/x", id: '3EB0FALL')
    expect(message.status).not_to eq('failed')
    expect(message.content_attributes).to include('whatsapp_transport' => 'web', 'whatsapp_transport_fallback' => true)
  end

  it 'resends a message without rich_message as before' do
    message = window_closed_status(accepted_by_meta({}))

    expect(client).to have_received(:send_text).with(session: 'hybrid-test', chat_id: '5511937016094@c.us', text: 'retorno', id: '3EB0FALL')
    expect(message.status).not_to eq('failed')
  end
end
