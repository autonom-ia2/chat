require 'rails_helper'

# chat#1473 (P5): `content_attributes.rich_message` do tipo `contact` (enviar um cartão de contato).
describe RichMessages::Types::Contact do
  let(:rich_message) { { type: 'contact', name: 'Recepção da Unidade Centro', phone: '+55 11 4000-0473' } }
  let(:meta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.cartao' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }
  let(:card) do
    { name: { formatted_name: 'Recepção da Unidade Centro', first_name: 'Recepção da Unidade Centro' },
      phones: [{ phone: '+55 11 4000-0473' }] }
  end

  def contact(changes = {})
    described_class.new(rich_message.merge(changes).stringify_keys)
  end

  def outgoing(conversation, attrs = {})
    create(:message, { message_type: :outgoing, content: nil, conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  it 'is the class of the contact type' do
    expect(RichMessages.type_class('contact')).to eq(described_class)
  end

  it 'has "name: phone" as text version' do
    expect(contact.fallback_text('')).to eq('Recepção da Unidade Centro: +55 11 4000-0473')
  end

  describe 'Meta payload' do
    it 'sends one contact with the name and the phone as typed' do
      expect(contact.whatsapp_cloud_payload('')).to eq(type: 'contacts', contacts: [card])
    end

    it 'sends the WhatsApp ID when it comes' do
      payload = contact(wa_id: '551140000473').whatsapp_cloud_payload('')

      expect(payload.dig(:contacts, 0, :phones)).to eq([{ phone: '+55 11 4000-0473', wa_id: '551140000473' }])
    end
  end

  describe 'validation' do
    it 'accepts phones with spaces, hyphens, dots and parentheses' do
      ['+5511940000473', '+55 (11) 94000-0473', '+1.650.555.1234'].each do |phone|
        expect(contact(phone: phone).error_for('')).to be_nil
      end
    end

    [['an empty', ''], ['a blank', '  ']].each do |title, blank|
      it "treats #{title} WhatsApp ID as absent, not as an error" do
        blank_wa_id = contact(wa_id: blank)

        expect(blank_wa_id.error_for('')).to be_nil
        expect(blank_wa_id.whatsapp_cloud_payload('')).to eq(type: 'contacts', contacts: [card])
      end
    end

    it 'accepts a tab in the name and free punctuation in the phone' do
      expect(contact(name: "Recepção\tCentro").error_for('')).to be_nil
      expect(contact(phone: '+55 (11) 4000.0473-').error_for('')).to be_nil
    end

    it 'accepts a name of 100 characters and phones of 8 and 15 digits' do
      expect(contact(name: 'a' * 100, phone: '+12345678').error_for(nil)).to be_nil
      expect(contact(phone: '+123456789012345').error_for('')).to be_nil
    end

    {
      'a body' => [{}, 'Fale com a recepção:', 'BODY_NOT_ALLOWED'],
      'a missing name' => [{ name: nil }, '', 'NAME_INVALID'],
      'a blank name' => [{ name: '  ' }, '', 'NAME_INVALID'],
      'a name above 100 characters' => [{ name: 'a' * 101 }, '', 'NAME_INVALID'],
      'a name with a line break' => [{ name: "Recepção\nCentro" }, '', 'NAME_INVALID'],
      'a name with a vertical tab' => [{ name: "Recepção\vCentro" }, '', 'NAME_INVALID'],
      'a name with a next line (U+0085)' => [{ name: "Recepção\u0085Centro" }, '', 'NAME_INVALID'],
      'a name with a line separator (U+2028)' => [{ name: "Recepção\u2028Centro" }, '', 'NAME_INVALID'],
      'a name with a paragraph separator (U+2029)' => [{ name: "Recepção\u2029Centro" }, '', 'NAME_INVALID'],
      'a missing phone' => [{ phone: nil }, '', 'PHONE_INVALID'],
      'a phone that is a number' => [{ phone: 5_511_940_000_473 }, '', 'PHONE_INVALID'],
      'a phone without the country code sign' => [{ phone: '11 4000-0473' }, '', 'PHONE_INVALID'],
      'a phone with letters' => [{ phone: '+55 11 4000-ABCD' }, '', 'PHONE_INVALID'],
      'a phone with fewer than 8 digits' => [{ phone: '+1234567' }, '', 'PHONE_INVALID'],
      'a phone with more than 15 digits' => [{ phone: '+1234567890123456' }, '', 'PHONE_INVALID'],
      'a phone with a plus sign in the middle' => [{ phone: '+55+11940000473' }, '', 'PHONE_INVALID'],
      'a WhatsApp ID with a plus sign' => [{ wa_id: '+551140000473' }, '', 'WA_ID_INVALID'],
      'a WhatsApp ID that is a number' => [{ wa_id: 551_140_000_473 }, '', 'WA_ID_NOT_TEXT'],
      'a WhatsApp ID that is a list' => [{ wa_id: ['551140000473'] }, '', 'WA_ID_INVALID'],
      'a WhatsApp ID with fewer than 8 digits' => [{ wa_id: '1234567' }, '', 'WA_ID_INVALID']
    }.each do |title, (changes, body, error)|
      it "refuses #{title}" do
        expect(contact(changes).error_for(body)).to eq(described_class.const_get(error))
      end
    end
  end

  context 'with a WhatsApp Cloud inbox and the 24h window open' do
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

    it 'sends one contacts message with the exact payload' do
      expected = { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094', type: 'contacts', contacts: [card] }
      request = stub_request(:post, meta_url).with(body: expected.to_json).to_return(meta_ok)

      message = deliver(outgoing(conversation))

      expect(request).to have_been_requested.once
      expect(message.source_id).to eq('wamid.cartao')
      expect(message.status).not_to eq('failed')
    end

    it 'fails a message with a body, instead of sending two messages or dropping the body' do
      message = deliver(outgoing(conversation, content: 'Fale com a recepção:'))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(described_class::BODY_NOT_ALLOWED)
      expect(a_request(:post, meta_url)).not_to have_been_made
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

    it 'sends "name: phone" as text' do
      text = 'Recepção da Unidade Centro: +55 11 4000-0473'
      request = stub_request(:post, 'https://waba.360dialog.io/v1/messages')
                .with(body: { 'to' => '123456789', 'text' => { 'body' => text }, 'type' => 'text' }.to_json)
                .to_return(status: 200, body: { 'messages' => [{ 'id' => 'd360' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      message = outgoing(conversation)
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_requested.once
      expect(message.reload.status).not_to eq('failed')
    end
  end

  describe 'creation through the API', type: :request do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.account) }
    let(:agent) { create(:user, account: channel.account, role: :administrator) }

    def create_message(params)
      post api_v1_account_conversation_messages_url(account_id: channel.account.id, conversation_id: conversation.display_id),
           params: params, headers: agent.create_new_auth_token, as: :json
    end

    it 'creates a contact without body' do
      expect { create_message(content: '', content_attributes: { rich_message: rich_message }) }.to change(Message, :count).by(1)

      expect(response).to have_http_status(:success)
    end

    it 'answers 422 with the reason and creates nothing for an invalid phone' do
      invalid = rich_message.merge(phone: '11 4000-0473')

      expect { create_message(content: '', content_attributes: { rich_message: invalid }) }.not_to change(Message, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(described_class::PHONE_INVALID)
    end
  end
end
