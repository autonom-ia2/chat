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

  it 'limits the channel call to a few seconds' do
    allow(HTTParty).to receive(:post).and_call_original

    described_class.perform_now(conversation, 'on', Time.current)

    expect(described_class::CHANNEL_TIMEOUT_SECONDS).to eq(3)
    expect(HTTParty).to have_received(:post).with(meta_typing_url, hash_including(timeout: 3))
  end

  it 'drops a request older than the limit' do
    described_class.perform_now(conversation, 'on', (described_class::MAX_AGE + 1.second).ago)

    expect(WebMock).not_to have_requested(:post, meta_typing_url)
  end
end
