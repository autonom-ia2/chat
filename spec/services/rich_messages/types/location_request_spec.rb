require 'rails_helper'

# chat#1473 (P5): `content_attributes.rich_message` do tipo `location_request` (pedir a localização ao cliente).
describe RichMessages::Types::LocationRequest do
  let(:rich_message) { { type: 'location_request' } }
  let(:body) { 'Para achar a unidade mais perto, me envie onde você está.' }
  let(:meta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.pedido' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

  def outgoing(conversation, attrs = {})
    create(:message, { message_type: :outgoing, content: body, conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  it 'is the class of the location_request type' do
    expect(RichMessages.type_class('location_request')).to eq(described_class)
  end

  it 'has a text version that is only the body' do
    expect(described_class.new({}).fallback_text(body)).to eq('')
  end

  context 'with a WhatsApp Cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, account: inbox.account) }

    def deliver(message)
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      message.reload
    end

    before do
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: inbox.account)
    end

    it 'sends one interactive location_request_message with the exact payload' do
      expected = {
        messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094', type: 'interactive',
        interactive: { type: 'location_request_message', body: { text: body }, action: { name: 'send_location' } }
      }
      request = stub_request(:post, meta_url).with(body: expected.to_json).to_return(meta_ok)

      message = deliver(outgoing(conversation))

      expect(request).to have_been_requested.once
      expect(message.source_id).to eq('wamid.pedido')
      expect(message.status).not_to eq('failed')
    end

    it 'accepts a body of exactly 1024 characters' do
      stub_request(:post, meta_url).to_return(meta_ok)

      expect(deliver(outgoing(conversation, content: 'a' * 1024)).status).not_to eq('failed')
    end

    {
      'a blank body' => [{ content: '' }, described_class::BODY_BLANK],
      'a missing body' => [{ content: nil }, described_class::BODY_BLANK],
      'a body above 1024 characters' => [{ content: 'a' * 1025 }, described_class::BODY_TOO_LONG]
    }.each do |title, (changes, error)|
      it "fails the message without sending anything for #{title}" do
        message = deliver(outgoing(conversation, changes))

        expect(message.status).to eq('failed')
        expect(message.external_error).to eq(error)
        expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
      end
    end
  end

  context 'with a WhatsApp inbox from another provider (360dialog)' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '123456789') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }

    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account)
    end

    it 'sends only the body as text' do
      request = stub_request(:post, 'https://waba.360dialog.io/v1/messages')
                .with(body: { 'to' => '123456789', 'text' => { 'body' => body }, 'type' => 'text' }.to_json)
                .to_return(status: 200, body: { 'messages' => [{ 'id' => 'd360' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      message = outgoing(conversation)
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_requested.once
      expect(message.reload.status).not_to eq('failed')
    end
  end
end
