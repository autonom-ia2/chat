require 'rails_helper'

RSpec.describe Meta::ConversionsApiClient do
  subject(:client) { described_class.new(access_token: token, dataset_id: dataset_id, api_version: api_version) }

  # 44 chars, all token-safe -> matches SENSITIVE_PATTERN and must be redacted.
  let(:token) { "EAAG#{'x' * 40}" }
  let(:dataset_id) { 'DS123' }
  let(:api_version) { 'v22.0' }
  let(:endpoint) { "https://graph.facebook.com/#{api_version}/#{dataset_id}/events" }
  let(:event) { { 'event_name' => 'Purchase', 'event_time' => 123, 'ctwa_clid' => 'CLID1' } }

  describe '#post_events' do
    it 'posts the events wrapped in a data array with the token only in the Authorization header' do
      stub = stub_request(:post, endpoint)
             .with(headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }, body: { data: [event] }.to_json)
             .to_return(status: 200, body: '{"events_received":1}', headers: { 'Content-Type' => 'application/json' })

      result = client.post_events([event])

      expect(stub).to have_been_requested
      # The token must never travel in the query string (leaks via access logs/proxies).
      expect(a_request(:post, endpoint).with(query: hash_including('access_token' => token))).not_to have_been_made
      expect(result.ok).to be(true)
      expect(result.http_code).to eq(200)
      expect(result.error).to be_nil
      expect(result.body).to include('events_received')
    end

    it 'redacts any token-shaped substring echoed back in an error body' do
      stub_request(:post, endpoint)
        .to_return(status: 400, body: %({"error":{"message":"Invalid OAuth access token #{token}"}}))

      result = client.post_events([event])

      expect(result.ok).to be(false)
      expect(result.http_code).to eq(400)
      expect(result.error).to include('<REDACTED>')
      expect(result.error).not_to include(token)
    end

    it "exposes Meta's numeric error code, and nil when the body has none it can read" do
      {
        '{"error":{"code":190,"message":"expired"}}' => 190,
        '{"error":{"code":200}}' => 200,
        '{"error":"plain text"}' => nil,
        'not json' => nil
      }.each do |body, code|
        stub_request(:post, endpoint).to_return(status: 400, body: body)

        result = client.post_events([event])

        expect([result.ok, result.http_code, result.error_code]).to eq([false, 400, code]), body
      end
    end

    it "exposes Meta's error subcode, used to tell a dataset that no longer exists (#2738)" do
      stub_request(:post, endpoint).to_return(status: 400, body: '{"error":{"code":100,"error_subcode":33,"message":"does not exist"}}')

      result = client.post_events([event])

      expect([result.error_code, result.error_subcode]).to eq([100, 33])
    end

    it 'never calls a 5xx a dataset that is gone, even with 100/33 in the body (#2799)' do
      stub_request(:post, endpoint).to_return(status: 500, body: '{"error":{"code":100,"error_subcode":33}}')

      expect(client.post_events([event])).to have_attributes(unknown_outcome: true, dataset_gone?: false)
    end

    it 'keeps an answer already read when closing the connection fails' do
      stub_request(:post, endpoint).to_return(status: 200, body: '{"events_received":1}')
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |http| allow(http).to receive(:finish).and_raise(IOError) }
      end

      expect(client.post_events([event])).to have_attributes(ok: true, http_code: 200)
    end

    it 'has no error code on success' do
      stub_request(:post, endpoint).to_return(status: 200, body: '{"events_received":1}')

      expect(client.post_events([event]).error_code).to be_nil
    end

    # Fails while opening the connection (TCP or the SSL handshake): nothing of the request left.
    def fail_on_connect(error)
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |http| allow(http).to receive(:start).and_raise(error) }
      end
    end

    it 'never surfaces the token when the HTTP call raises' do
      fail_on_connect(StandardError.new("network down token=#{token}"))

      result = client.post_events([event])

      expect(result.ok).to be(false)
      expect(result.http_code).to be_nil
      expect(result.error).to include('<REDACTED>')
      expect(result.error).not_to include(token)
    end

    it 'marks the outcome unknown when the call may have reached Meta (#2738)' do
      [Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNRESET, EOFError].each do |error|
        stub_request(:post, endpoint).to_raise(error)

        expect(client.post_events([event]).unknown_outcome).to be(true), error.name
      end
    end

    it 'marks the outcome unknown on an SSL error after the connection opened: the body may have left (#2799)' do
      stub_request(:post, endpoint).to_raise(OpenSSL::SSL::SSLError)

      expect(client.post_events([event])).to have_attributes(ok: false, unknown_outcome: true)
    end

    it 'keeps the outcome known when the connection never opened' do
      [Net::OpenTimeout, SocketError, Errno::ECONNREFUSED].each do |error|
        fail_on_connect(error)

        expect(client.post_events([event])).to have_attributes(ok: false, unknown_outcome: false), error.name
      end
    end

    it 'keeps the outcome known when the SSL handshake fails: no request was sent, so it can be sent again (#2799)' do
      fail_on_connect(OpenSSL::SSL::SSLError.new('handshake failure'))

      expect(client.post_events([event])).to have_attributes(ok: false, http_code: nil, unknown_outcome: false)
    end

    it 'marks the outcome unknown when Meta answers with a server error: it may have kept the event (#2799)' do
      [500, 502, 503, 504].each do |status|
        stub_request(:post, endpoint).to_return(status: status, body: '{"error":{"code":2,"message":"Service temporarily unavailable"}}')

        result = client.post_events([event])

        expect(result).to have_attributes(ok: false, http_code: status, error_code: 2, unknown_outcome: true), status.to_s
      end
    end

    it 'keeps the outcome known when Meta answers' do
      stub_request(:post, endpoint).to_return(status: 400, body: '{"error":{"code":100}}')

      expect(client.post_events([event]).unknown_outcome).to be_falsey
    end
  end

  describe 'api_version resolution' do
    it 'falls back to the shared WhatsApp API version when none is given' do
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', described_class::DEFAULT_API_VERSION).and_return('v20.0')
      resolved = described_class.new(access_token: token, dataset_id: dataset_id)
      stub = stub_request(:post, "https://graph.facebook.com/v20.0/#{dataset_id}/events").to_return(status: 200, body: '{}')

      resolved.post_events([event])

      expect(stub).to have_been_requested
    end
  end
end
