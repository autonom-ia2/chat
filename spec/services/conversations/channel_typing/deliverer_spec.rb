require 'rails_helper'

# chat#1442 — "digitando" no canal da conversa, pedido pelo robô.
describe Conversations::ChannelTyping::Deliverer do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:meta_typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }

  def conversation_in(inbox, source_id)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def deliver(conversation, typing_status)
    described_class.new(conversation: conversation, typing_status: typing_status).perform
  end

  context 'when the conversation is on WhatsApp Cloud' do
    let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
    let(:conversation) { conversation_in(channel.inbox, '5511999990000') }

    before { stub_request(:post, meta_typing_url).to_return(status: 200, body: '{}') }

    it 'sends the typing indicator for the last incoming message' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.OLD',
                       created_at: 2.minutes.ago)
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST',
                       created_at: 1.minute.ago)
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, source_id: 'wamid.OUT')

      deliver(conversation, 'on')

      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(
        headers: { 'Authorization' => 'Bearer test_key' },
        body: { messaging_product: 'whatsapp', status: 'read', message_id: 'wamid.LAST', typing_indicator: { type: 'text' } }.to_json
      )
    end

    it 'marks the read as made by the system up to the marked message, so it does not count as read on the phone (#2246)' do
      last = create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming,
                              source_id: 'wamid.LAST')
      account.enable_features!(ConversaCanal::VistaNoCelular::FLAG)
      Redis::Alfred.delete(ConversaCanal::LeituraDoSistema.chave(conversation))

      deliver(conversation, 'on')

      expect(ConversaCanal::LeituraDoSistema.ate(conversation)).to eq(last.reload.created_at)
    ensure
      Redis::Alfred.delete(ConversaCanal::LeituraDoSistema.chave(conversation))
    end

    it 'leaves no system read mark and sends the same typing request with the flag off (#2246)' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')

      deliver(conversation, 'on')

      expect(ConversaCanal::LeituraDoSistema.ate(conversation)).to be_nil
      expect(WebMock).to have_requested(:post, meta_typing_url).once.with(
        body: { messaging_product: 'whatsapp', status: 'read', message_id: 'wamid.LAST', typing_indicator: { type: 'text' } }.to_json
      )
    end

    it 'does nothing when the installation turned channel typing off' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')

      with_modified_env AI_HUMANIZE_CHANNEL_TYPING: 'false' do
        expect(described_class.supports?(conversation)).to be(false)
        deliver(conversation, 'on')
      end

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'does nothing on typing off, because Meta has no typing off' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')

      deliver(conversation, 'off')

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'does nothing when no incoming message has a source_id' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: nil)
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, source_id: 'wamid.OUT')

      deliver(conversation, 'on')

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
    end

    it 'logs the refusal from Meta without the token and does not raise' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')
      stub_request(:post, meta_typing_url).to_return(status: 401, body: '{"error":{"message":"Invalid OAuth access token"}}')
      allow(Rails.logger).to receive(:warn)

      expect { deliver(conversation, 'on') }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).with("[channel_typing] refused conversation=#{conversation.id} status=401")
    end

    it 'does not raise when the network fails' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')
      stub_request(:post, meta_typing_url).to_timeout

      expect { deliver(conversation, 'on') }.not_to raise_error
    end

    it 'passes the given timeout to the channel call and logs a timeout error without raising' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')
      stub_request(:post, meta_typing_url).to_timeout
      allow(HTTParty).to receive(:post).and_call_original
      allow(Rails.logger).to receive(:warn)

      expect { described_class.new(conversation: conversation, typing_status: 'on', timeout: 3).perform }.not_to raise_error

      expect(HTTParty).to have_received(:post).with(meta_typing_url, hash_including(timeout: 3))
      expect(Rails.logger).to have_received(:warn).with('[whatsapp][typing] failed phone=123456789 Net::OpenTimeout')
    end

    it 'sends no timeout option when none is given' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')
      allow(HTTParty).to receive(:post).and_call_original

      deliver(conversation, 'on')

      expect(HTTParty).to have_received(:post).with(meta_typing_url, hash_excluding(:timeout))
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

    { 'on' => 'typing_on', 'off' => 'typing_off' }.each do |typing_status, sender_action|
      it "sends #{sender_action} to the contact on typing #{typing_status}" do
        deliver(conversation, typing_status)

        expect(WebMock).to have_requested(:post, instagram_url).once.with(
          query: { access_token: channel.access_token },
          body: { recipient: { id: 'ig-contact-1' }, sender_action: sender_action }
        )
      end
    end

    it 'passes the given timeout to the channel call and logs a timeout error without raising' do
      stub_request(:post, instagram_url).with(query: { access_token: channel.access_token }).to_timeout
      allow(HTTParty).to receive(:post).and_call_original
      allow(Rails.logger).to receive(:warn)

      expect { described_class.new(conversation: conversation, typing_status: 'on', timeout: 3).perform }.not_to raise_error

      expect(HTTParty).to have_received(:post).with(instagram_url, hash_including(timeout: 3))
      expect(Rails.logger).to have_received(:warn).with('[instagram][typing] failed Net::OpenTimeout')
    end

    it 'sends no timeout option when none is given' do
      allow(HTTParty).to receive(:post).and_call_original

      deliver(conversation, 'on')

      expect(HTTParty).to have_received(:post).with(instagram_url, hash_excluding(:timeout))
    end

    it 'does nothing for an unknown typing status' do
      deliver(conversation, 'maybe')

      expect(WebMock).not_to have_requested(:post, instagram_url).with(query: hash_including({}))
    end

    it 'stays quiet for a legacy conversation without contact_inbox' do
      allow(conversation).to receive(:contact_inbox).and_return(nil)
      allow(Rails.logger).to receive(:warn)

      deliver(conversation, 'on')

      expect(Rails.logger).not_to have_received(:warn)
      expect(WebMock).not_to have_requested(:post, instagram_url).with(query: hash_including({}))
    end
  end

  context 'when the channel has no typing delivery' do
    let(:whatsapp_360) { create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false) }
    let(:unsupported_inboxes) do
      [
        whatsapp_360.inbox,
        create(:inbox, account: account, channel: create(:channel_api, account: account)),
        create(:inbox, account: account, channel: create(:channel_email, account: account)),
        create(:inbox, account: account, channel: create(:channel_widget, account: account))
      ]
    end

    it 'does not support the conversation and calls nothing' do
      allow(Rails.logger).to receive(:warn)

      unsupported_inboxes.each do |inbox|
        conversation = conversation_in(inbox, "5511#{inbox.id.to_s.rjust(9, '0')}")
        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, source_id: 'wamid.LAST')

        expect(described_class.supports?(conversation)).to be(false)
        deliver(conversation, 'on')
      end

      # Nenhuma URL está registrada neste contexto: qualquer chamada HTTP faria o WebMock levantar aqui.
      expect(WebMock).not_to have_requested(:post, meta_typing_url)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end
end
