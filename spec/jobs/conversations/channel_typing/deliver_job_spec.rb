require 'rails_helper'

# chat#1442 — "digitando" que chega tarde é pior que não chegar: pedido velho é descartado.
RSpec.describe Conversations::ChannelTyping::DeliverJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:meta_typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }

  before do
    stub_request(:post, meta_typing_url).to_return(status: 200, body: '{}')
    create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming, source_id: 'wamid.LAST')
  end

  it 'runs on a queue below the one that sends replies' do
    expect(described_class.new.queue_name).to eq('medium')
    expect(SendReplyJob.new.queue_name).to eq('high')
  end

  it 'delivers a fresh request' do
    described_class.perform_now(conversation, 'on', (described_class::MAX_AGE - 1.second).ago)

    expect(WebMock).to have_requested(:post, meta_typing_url).once
  end

  it 'passes its channel timeout to the channel call' do
    allow(HTTParty).to receive(:post).and_call_original

    described_class.perform_now(conversation, 'on', Time.current)

    expect(HTTParty).to have_received(:post).with(meta_typing_url, hash_including(timeout: described_class::CHANNEL_TIMEOUT_SECONDS))
  end

  it 'drops a request older than the limit and logs it' do
    allow(Rails.logger).to receive(:info)

    described_class.perform_now(conversation, 'on', (described_class::MAX_AGE + 1.second).ago)

    expect(WebMock).not_to have_requested(:post, meta_typing_url)
    expect(Rails.logger).to have_received(:info)
      .with(a_string_starting_with("[channel_typing] dropped conversation=#{conversation.id} status=on reason=stale age_seconds=11"))
  end

  context 'when the reply already went out after the request' do
    let(:requested_at) { 2.seconds.ago }

    before { create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing) }

    it 'drops typing on, so it does not show typing again, and logs it' do
      allow(Rails.logger).to receive(:info)

      described_class.perform_now(conversation, 'on', requested_at)

      expect(WebMock).not_to have_requested(:post, meta_typing_url)
      expect(Rails.logger).to have_received(:info)
        .with(a_string_starting_with("[channel_typing] dropped conversation=#{conversation.id} status=on reason=already_replied age_seconds="))
    end
  end

  it 'delivers typing on when the only outgoing message is older than the request' do
    create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, created_at: 1.minute.ago)

    described_class.perform_now(conversation, 'on', 2.seconds.ago)

    expect(WebMock).to have_requested(:post, meta_typing_url).once
  end

  it 'does not count a private note as the reply' do
    create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing, private: true)

    described_class.perform_now(conversation, 'on', 2.seconds.ago)

    expect(WebMock).to have_requested(:post, meta_typing_url).once
  end

  context 'when the conversation is on Instagram' do
    let(:channel) { create(:channel_instagram, account: account) }
    let(:instagram_url) { "https://graph.instagram.com/v22.0/#{channel.instagram_id}/messages" }

    before { stub_request(:post, instagram_url).with(query: { access_token: channel.access_token }).to_return(status: 200, body: '{}') }

    it 'still delivers typing off after the reply went out' do
      create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :outgoing)

      described_class.perform_now(conversation, 'off', 2.seconds.ago)

      expect(WebMock).to have_requested(:post, instagram_url).with(query: { access_token: channel.access_token }).once
    end
  end
end
