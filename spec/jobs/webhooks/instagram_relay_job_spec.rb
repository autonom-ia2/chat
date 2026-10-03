require 'rails_helper'

RSpec.describe Webhooks::InstagramRelayJob do
  let(:url) { 'https://other-stack.example.com/webhooks/instagram' }
  let(:body) { '{"object":"instagram","entry":[]}' }
  let(:signature) { 'sha256=abc' }

  it 'posts the original body and signature with the relay marker' do
    stub = stub_request(:post, url)
           .with(body: body, headers: { 'X-Hub-Signature-256' => signature, described_class::RELAY_HEADER => '1' })
           .to_return(status: 200)

    described_class.perform_now(url, body, signature)

    expect(stub).to have_been_requested
  end

  it 'raises when the destination rejects the event so it is retried' do
    stub_request(:post, url).to_return(status: 500)

    expect { described_class.new.perform(url, body, signature) }
      .to raise_error(RuntimeError) { |error| expect(error.message).to include('HTTP 500') }
  end
end
