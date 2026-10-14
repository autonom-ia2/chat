require 'rails_helper'

# chat#1442 (entrega 2) — "digitando" na caixa WhatsApp API (Channel::Api provisionada para WAHA).
describe Conversations::ChannelTyping::Deliverer do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511888880000' }) }
  let(:inbox) { channel.inbox }
  let(:chat_id) { '5511999990000@c.us' }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'waha_whatsapp_chat_id' => chat_id }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:start_url) { 'https://waha.example/api/startTyping' }
  let(:stop_url) { 'https://waha.example/api/stopTyping' }
  let(:json) { { status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}' } }

  around { |example| with_modified_env(WAHA_API_URL: 'https://waha.example', WAHA_API_KEY: 'waha-key') { example.run } }

  before do
    stub_request(:post, start_url).to_return(json)
    stub_request(:post, stop_url).to_return(json)
    allow(Rails.logger).to receive(:warn)
  end

  def deliver(typing_status, **)
    described_class.new(conversation: conversation, typing_status: typing_status, **).perform
  end

  it 'starts typing on the session of the inbox for the chat of the contact' do
    deliver('on')

    expect(WebMock).to have_requested(:post, start_url).once.with(
      headers: { 'X-Api-Key' => 'waha-key' }, body: { session: '5511888880000', chatId: chat_id }.to_json
    )
    expect(WebMock).not_to have_requested(:post, stop_url)
    expect(Rails.logger).not_to have_received(:warn)
  end

  it 'stops typing on typing off' do
    deliver('off')

    expect(WebMock).to have_requested(:post, stop_url).once.with(body: { session: '5511888880000', chatId: chat_id }.to_json)
    expect(WebMock).not_to have_requested(:post, start_url)
  end

  it 'does not call the engine for an unknown typing status' do
    deliver('maybe')

    expect(WebMock).not_to have_requested(:post, start_url)
    expect(WebMock).not_to have_requested(:post, stop_url)
    expect(Rails.logger).not_to have_received(:warn)
  end

  it 'passes the given timeout to the engine call and keeps the default of the client without one' do
    allow(HTTParty).to receive(:post).and_call_original

    deliver('on', timeout: 3)
    deliver('on')

    expect(HTTParty).to have_received(:post).with(start_url, hash_including(timeout: 3)).once
    expect(HTTParty).to have_received(:post).with(start_url, hash_including(timeout: Waha::Client::DEFAULT_TIMEOUT)).once
  end

  context 'when the inbox has no session' do
    let(:channel) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }) }

    it 'does nothing' do
      deliver('on')

      expect(WebMock).not_to have_requested(:post, start_url)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  context 'when the contact has no WhatsApp chat id yet' do
    let(:contact) { create(:contact, account: account) }

    it 'does nothing' do
      deliver('on')

      expect(WebMock).not_to have_requested(:post, start_url)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  %w[120363000000000000@g.us status@broadcast 120363000000000000@newsletter].each do |non_direct_chat_id|
    context "when the chat is not one to one (#{non_direct_chat_id})" do
      let(:chat_id) { non_direct_chat_id }

      it 'does not show typing' do
        deliver('on')

        expect(WebMock).not_to have_requested(:post, start_url)
        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end

  context 'when the chat id of the contact is a lid' do
    let(:chat_id) { '123456789012345@lid' }

    it 'sends the lid as it is' do
      deliver('on')

      expect(WebMock).to have_requested(:post, start_url).once.with(body: { session: '5511888880000', chatId: chat_id }.to_json)
    end
  end

  context 'when the contact only has the jid' do
    let(:contact) { create(:contact, account: account, custom_attributes: { 'waha_whatsapp_jid' => '5511977770000@c.us' }) }

    it 'falls back to the jid' do
      deliver('on')

      expect(WebMock).to have_requested(:post, start_url).once.with(body: { session: '5511888880000', chatId: '5511977770000@c.us' }.to_json)
    end
  end

  context 'when only the jid says it is a group' do
    let(:contact) { create(:contact, account: account, custom_attributes: { 'waha_whatsapp_jid' => '120363000000000000@g.us' }) }

    it 'does not show typing' do
      deliver('on')

      expect(WebMock).not_to have_requested(:post, start_url)
      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  { 404 => 'Waha::Client::NotFound', 422 => 'Waha::Client::Error' }.each do |status, error_class|
    it "logs only the error class when the engine answers #{status}" do
      stub_request(:post, start_url).to_return(status: status, body: 'session 5511888880000 not found')

      expect { deliver('on') }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).once.with("[channel_typing] failed conversation=#{conversation.id} #{error_class}")
    end
  end

  it 'logs only the error class when the engine refuses' do
    stub_request(:post, start_url).to_return(status: 500, body: 'session 5511888880000 is not WORKING')

    expect { deliver('on') }.not_to raise_error

    expect(Rails.logger).to have_received(:warn).once.with("[channel_typing] failed conversation=#{conversation.id} Waha::Client::Error")
  end

  it 'logs only the error class when the engine does not answer in time' do
    stub_request(:post, start_url).to_raise(Net::ReadTimeout)

    expect { deliver('on', timeout: 3) }.not_to raise_error

    expect(Rails.logger).to have_received(:warn).once.with("[channel_typing] failed conversation=#{conversation.id} Waha::Client::Timeout")
  end

  it 'is not supported when the installation turned channel typing off' do
    with_modified_env AI_HUMANIZE_CHANNEL_TYPING: 'false' do
      expect(described_class.supports?(conversation)).to be(false)
      deliver('on')
    end

    expect(WebMock).not_to have_requested(:post, start_url)
  end

  it 'is not supported when the WAHA integration is not configured' do
    with_modified_env WAHA_API_KEY: '' do
      expect(described_class.supports?(conversation)).to be(false)
      deliver('on')
    end

    expect(WebMock).not_to have_requested(:post, start_url)
  end

  context 'when the API inbox is not a WAHA one' do
    let(:channel) { create(:channel_api, account: account) }

    it 'is not supported' do
      expect(described_class.supports?(conversation)).to be(false)
    end
  end

  describe 'through the job' do
    let(:job) { Conversations::ChannelTyping::DeliverJob }

    it 'limits the engine call with the channel timeout of the job' do
      allow(HTTParty).to receive(:post).and_call_original

      job.perform_now(conversation, 'on', Time.current)

      expect(HTTParty).to have_received(:post).with(start_url, hash_including(timeout: job::CHANNEL_TIMEOUT_SECONDS)).once
    end

    it 'drops typing on when the reply already went out' do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing)

      job.perform_now(conversation, 'on', 2.seconds.ago)

      expect(WebMock).not_to have_requested(:post, start_url)
    end

    it 'does not fail nor retry when the engine does not answer in time' do
      stub_request(:post, start_url).to_raise(Net::ReadTimeout)

      expect { job.perform_now(conversation, 'on', Time.current) }.not_to raise_error

      expect(job).not_to have_been_enqueued
      expect(Rails.logger).to have_received(:warn).once.with("[channel_typing] failed conversation=#{conversation.id} Waha::Client::Timeout")
    end
  end
end
