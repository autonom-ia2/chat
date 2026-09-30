require 'rails_helper'

RSpec.describe Crm::Ai::ResponsesClient do
  let(:client) { described_class.new(credential: { api_key: 'test-key' }) }
  let(:url) { 'https://api.openai.com/v1/responses' }
  let(:payload) { { output_text: 'ok', model: 'gpt-6.1-sol', output: [] }.to_json }
  let(:params) { { model: 'gpt-6.1-sol', instructions: 'instruction', input: 'input' } }

  before do
    allow(Resolv).to receive(:getaddresses).with('api.openai.com').and_return(['104.18.1.1'])
    allow(client).to receive(:sleep)
  end

  it 'uses 180 seconds and disables the transport implicit retry' do
    stub_request(:post, url).to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
    allow(HTTParty).to receive(:post).and_call_original

    expect(client.create(**params)[:text]).to eq('ok')
    expect(HTTParty).to have_received(:post).with(url, hash_including(timeout: 180, max_retries: 0))
  end

  [408, 429, 500, 502, 503, 504].each do |status|
    it "recovers from HTTP #{status} with at most two retries" do
      request = stub_request(:post, url).to_return(status: status).then
                                        .to_return(status: status).then
                                        .to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
      expect(client.create(**params)[:text]).to eq('ok')
      expect(request).to have_been_requested.times(3)
      expect(client).to have_received(:sleep).with(1).once
      expect(client).to have_received(:sleep).with(2).once
    end
  end

  [400, 401, 403, 404, 422].each do |status|
    it "does not retry permanent HTTP #{status}" do
      request = stub_request(:post, url).to_return(status: status, body: '{"error":{"message":"rejected"}}',
                                                   headers: { 'Content-Type' => 'application/json' })
      expect { client.create(**params) }.to raise_error(described_class::Error)
      expect(request).to have_been_requested.once
      expect(client).not_to have_received(:sleep)
    end
  end

  it 'stops after three attempts on persistent HTTP failure' do
    request = stub_request(:post, url).to_return(status: 503)
    expect { client.create(**params) }.to raise_error(described_class::Error)
    expect(request).to have_been_requested.times(3)
  end

  [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, EOFError, Errno::ECONNRESET].each do |error|
    it "bounds #{error.name} retries and preserves the error contract" do
      request = stub_request(:post, url).to_raise(error)
      expect { client.create(**params) }.to raise_error(described_class::Error) { |e| expect(e.message).to start_with('network_timeout:') }
      expect(request).to have_been_requested.times(3)
    end
  end

  it 'recovers from a timeout without changing the request' do
    request = stub_request(:post, url).with { |r| JSON.parse(r.body)['model'] == 'gpt-6.1-sol' }
                                      .to_raise(Net::ReadTimeout).then
                                      .to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
    expect(client.create(**params)[:text]).to eq('ok')
    expect(request).to have_been_requested.twice
  end

  it 'does not retry a successful HTTP response with unusable output' do
    request = stub_request(:post, url).to_return(body: '{"output":[]}', headers: { 'Content-Type' => 'application/json' })
    expect { client.create(**params) }.to raise_error(described_class::Error, 'empty_response')
    expect(request).to have_been_requested.once
  end

  it 'shares the retry budget across network and HTTP failures' do
    request = stub_request(:post, url).to_raise(Net::ReadTimeout).then.to_return(status: 503)
    expect { client.create(**params) }.to raise_error(described_class::Error)
    expect(request).to have_been_requested.times(3)
  end

  it 'does not rerun a tool when the next model request needs retrying' do
    tool_call = { output: [{ type: 'function_call', name: 'act', call_id: 'c1', arguments: '{}' }] }.to_json
    request = stub_request(:post, url).to_return(body: tool_call, headers: { 'Content-Type' => 'application/json' }).then
                                      .to_return(status: 503).then
                                      .to_return(body: payload, headers: { 'Content-Type' => 'application/json' })
    executions = 0
    result = client.create_with_tool_executor(**params, schema: nil, tools: [{ type: 'function', name: 'act' }]) do
      executions += 1
      [{ type: 'function_call_output', call_id: 'c1', output: 'done' }]
    end
    expect(result[:text]).to eq('ok')
    expect(executions).to eq(1)
    expect(request).to have_been_requested.times(3)
  end

  it 'retries background submission and preserves background parameters' do
    request = stub_request(:post, url).with { |r| JSON.parse(r.body).values_at('store', 'background') == [true, true] }
                                      .to_return(status: 503).then
                                      .to_return(body: '{"id":"resp_1","status":"queued"}', headers: { 'Content-Type' => 'application/json' })
    expect(client.create_background(**params)).to eq(id: 'resp_1', status: 'queued')
    expect(request).to have_been_requested.twice
  end

  it 'retrieves the actual model of a response started before the migration' do
    request = stub_request(:get, "#{url}/resp_1").to_return(status: 503).then
                                                 .to_return(body: '{"model":"gpt-5.6-sol","status":"completed","output_text":"old"}',
                                                            headers: { 'Content-Type' => 'application/json' })
    expect(client.retrieve('resp_1')).to include(model: 'gpt-5.6-sol', text: 'old')
    expect(request).to have_been_requested.twice
  end

  it 'bounds deletion retries too' do
    request = stub_request(:delete, "#{url}/resp_1").to_raise(Net::ReadTimeout)
    expect(client.delete('resp_1')).to be(false)
    expect(request).to have_been_requested.times(3)
  end
end
