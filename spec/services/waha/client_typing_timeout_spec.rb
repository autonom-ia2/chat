require 'rails_helper'

# chat#1442 — start_typing/stop_typing aceitam timeout por chamada; os outros POSTs seguem no padrão.
RSpec.describe Waha::Client do
  let(:config) { class_double(Waha::Config, api_url: 'https://waha.example', api_key: 'test-key') }
  let(:client) { described_class.new(config: config) }
  let(:json) { { status: 200, headers: { 'Content-Type' => 'application/json' }, body: '{}' } }

  before do
    %w[startTyping stopTyping sendText].each { |path| stub_request(:post, "https://waha.example/api/#{path}").to_return(json) }
    allow(HTTParty).to receive(:post).and_call_original
  end

  { start_typing: 'startTyping', stop_typing: 'stopTyping' }.each do |method, path|
    it "passes the per-call timeout of #{method} to HTTParty" do
      client.public_send(method, session: 'vendas', chat_id: '5511912345678@c.us', timeout: 3)

      expect(HTTParty).to have_received(:post).with("https://waha.example/api/#{path}", hash_including(timeout: 3)).once
      expect(WebMock).to have_requested(:post, "https://waha.example/api/#{path}")
        .with(body: { session: 'vendas', chatId: '5511912345678@c.us' }.to_json)
    end

    it "keeps the default timeout of #{method} when none is given" do
      client.public_send(method, session: 'vendas', chat_id: '5511912345678@c.us')

      expect(HTTParty).to have_received(:post)
        .with("https://waha.example/api/#{path}", hash_including(timeout: described_class::DEFAULT_TIMEOUT)).once
    end
  end

  it 'keeps the default timeout of the other POSTs' do
    client.send_text(session: 'vendas', chat_id: '5511912345678@c.us', text: 'oi', id: '3EB0')

    expect(HTTParty).to have_received(:post)
      .with('https://waha.example/api/sendText', hash_including(timeout: described_class::DEFAULT_TIMEOUT)).once
  end

  it 'raises Waha::Client::Timeout when the typing call gets no answer' do
    stub_request(:post, 'https://waha.example/api/startTyping').to_raise(Net::ReadTimeout)

    expect { client.start_typing(session: 'vendas', chat_id: '5511912345678@c.us', timeout: 3) }
      .to raise_error(Waha::Client::Timeout)
  end
end
