require 'rails_helper'

# Contrato do TypingIndicator do agente nativo: widget pelo evento do painel, WhatsApp Cloud e Instagram
# pelo envio por canal (delegado a Conversations::ChannelTyping::Deliverer desde o chat#1442).
describe Autonomia::Agents::Operate::TypingIndicator do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent_inbox) { Struct.new(:agent_bot).new(agent_bot) }
  let(:meta_typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }

  def conversation_in(inbox, source_id)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def indicator(conversation)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox)
  end

  context 'when the conversation is on the web widget' do
    let(:conversation) { create(:conversation, account: account) }

    before { allow(Rails.configuration.dispatcher).to receive(:dispatch) }

    it 'dispatches typing on as the agent bot' do
      indicator(conversation).on

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(
        Conversation::CONVERSATION_TYPING_ON, kind_of(Time), { conversation: conversation, user: agent_bot, is_private: false }
      )
    end

    it 'dispatches typing off as the agent bot' do
      indicator(conversation).off

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(
        Conversation::CONVERSATION_TYPING_OFF, kind_of(Time), { conversation: conversation, user: agent_bot, is_private: false }
      )
    end

    it 'keeps the widget typing when the channel typing key is off' do
      with_modified_env AI_HUMANIZE_CHANNEL_TYPING: 'false' do
        indicator(conversation).on
      end

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).once.with(
        Conversation::CONVERSATION_TYPING_ON, kind_of(Time), { conversation: conversation, user: agent_bot, is_private: false }
      )
    end
  end

  context 'when the conversation is on WhatsApp Cloud' do
    let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
    let(:conversation) { conversation_in(channel.inbox, '5511999990000') }

    before do
      stub_request(:post, meta_typing_url).to_return(status: 200, body: '{}')
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
    end

    it 'sends the Meta typing indicator on typing on, without a panel event' do
      indicator(conversation).on

      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(
        body: { messaging_product: 'whatsapp', status: 'read', message_id: 'wamid.LAST', typing_indicator: { type: 'text' } }.to_json
      )
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Conversation::CONVERSATION_TYPING_ON, any_args)
    end

    it 'references the most recent incoming message, not the oldest' do
      conversation.messages.incoming.first.update!(created_at: 2.minutes.ago)
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.NEWER')

      indicator(conversation).on

      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(body: hash_including('message_id' => 'wamid.NEWER'))
    end

    it 'does nothing on typing off' do
      indicator(conversation).off

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'does nothing when the channel typing key is off' do
      with_modified_env AI_HUMANIZE_CHANNEL_TYPING: 'false' do
        indicator(conversation).on
      end

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'does not raise when the network fails' do
      stub_request(:post, meta_typing_url).to_timeout

      expect { indicator(conversation).on }.not_to raise_error
    end
  end

  context 'when the conversation is on Instagram' do
    let(:channel) { create(:channel_instagram, account: account) }
    let(:conversation) { conversation_in(channel.inbox, 'ig-contact-1') }
    let(:instagram_url) { "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages" }

    before do
      stub_request(:post, instagram_url).with(query: { access_token: channel.access_token }).to_return(status: 200, body: '{}')
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming)
    end

    it 'sends typing_on and typing_off to the contact' do
      indicator(conversation).on
      indicator(conversation).off

      %w[typing_on typing_off].each do |sender_action|
        expect(WebMock).to have_requested(:post, instagram_url).once.with(
          query: { access_token: channel.access_token },
          body: { recipient: { id: 'ig-contact-1' }, sender_action: sender_action }
        )
      end
    end
  end
end
