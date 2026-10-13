require 'rails_helper'

# chat#1442 (entrega 2) — caixa oficial com WhatsApp Híbrido (chat#1067): quando a resposta vai sair pelo
# WhatsApp API, o próprio envio já mostra "digitando"; a Meta não é chamada.
describe Conversations::ChannelTyping::Deliverer do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:meta_typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:last_inbound_at) { 30.hours.ago }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

  before do
    stub_request(:post, meta_typing_url).to_return(status: 200, body: '{}')
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: "hybrid-#{SecureRandom.hex(3)}", status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'wamid.LAST',
                     created_at: last_inbound_at)
  end

  def deliver(typing_status)
    described_class.new(conversation: conversation, typing_status: typing_status).perform
  end

  context 'when the 24h window is closed and the reply goes through the WhatsApp API' do
    it 'does not call Meta, because the send itself shows typing' do
      expect(conversation.whatsapp_api_reply?).to be(true)

      deliver('on')
      deliver('off')

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'does not call Meta for the native agent either' do
      agent_inbox = Struct.new(:agent_bot).new(create(:agent_bot, account: account))

      Autonomia::Agents::Operate::TypingIndicator.new(conversation: conversation, agent_inbox: agent_inbox).on

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'keeps calling Meta when the hybrid typing simulation is turned off' do
      with_modified_env WHATSAPP_HYBRID_TYPING: 'false' do
        deliver('on')
      end

      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(body: hash_including('message_id' => 'wamid.LAST'))
    end
  end

  context 'when the 24h window is open' do
    let(:last_inbound_at) { 1.minute.ago }

    it 'calls Meta as before' do
      expect(conversation.whatsapp_api_reply?).to be(false)

      deliver('on')

      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(body: hash_including('message_id' => 'wamid.LAST'))
    end
  end

  context 'when the account is not in the hybrid pilot' do
    it 'calls Meta as before' do
      with_modified_env WHATSAPP_HYBRID_ACCOUNT_IDS: '' do
        deliver('on')
      end

      expect(WebMock).to have_requested(:post, meta_typing_url).once
    end
  end
end
