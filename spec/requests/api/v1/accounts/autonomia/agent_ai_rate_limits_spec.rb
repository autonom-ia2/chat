require 'rails_helper'

RSpec.describe 'Autonomia AI rate limits', type: :request do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:api_token) { 'test-api-credential' }
  let(:request_headers) { { 'REMOTE_ADDR' => '198.51.100.10', 'HTTP_API_ACCESS_TOKEN' => api_token } }
  let(:rack_app) { Rack::MockRequest.new(Rack::Attack.new(->(_env) { [200, { 'content-type' => 'text/plain' }, ['allowed']] })) }

  around do |example|
    previous_store = Rack::Attack.cache.store
    previous_enabled = Rack::Attack.enabled
    Rack::Attack.cache.store = cache_store
    Rack::Attack.enabled = true
    travel_to(Time.utc(2026, 10, 7, 12, 0, 1)) { example.run }
  ensure
    Rack::Attack.cache.store = previous_store
    Rack::Attack.enabled = previous_enabled
  end

  shared_examples 'a bounded AI endpoint' do |suffix, limit|
    let(:path) { "/api/v1/accounts/42/autonomia/#{suffix}" }

    it 'allows its documented burst, then returns the existing 429 envelope' do
      limit.times { expect(rack_app.post(path, request_headers).status).to eq(200) }

      refused = rack_app.post(path, request_headers)

      expect(refused.status).to eq(429)
      expect(JSON.parse(refused.body).dig('error', 'code')).to eq('rate_limited')
      expect(refused['Retry-After'].to_i).to be_between(1, 60)
    end

    it 'keeps other accounts and credentials independent' do
      limit.times { rack_app.post(path, request_headers) }

      expect(rack_app.post(path, request_headers).status).to eq(429)
      expect(rack_app.post(path, request_headers.merge('HTTP_API_ACCESS_TOKEN' => 'another-test-credential')).status).to eq(200)
      expect(rack_app.post(path.sub('/42/', '/43/'), request_headers).status).to eq(200)
    end

    it 'does not apply the writing limit to GET or to a different action' do
      limit.times { rack_app.post(path, request_headers) }

      expect(rack_app.get(path, request_headers).status).to eq(200)
      expect(rack_app.post("#{path}/other", request_headers).status).to eq(200)
    end
  end

  describe 'opening a builder' do
    it_behaves_like 'a bounded AI endpoint', 'build_threads', 60
  end

  describe 'answering a builder' do
    it_behaves_like 'a bounded AI endpoint', 'build_threads/7/messages', 60
  end

  describe 'retrying a builder' do
    it_behaves_like 'a bounded AI endpoint', 'build_threads/7/retry', 60
  end

  describe 'testing an agent' do
    it_behaves_like 'a bounded AI endpoint', 'agents/7/test', 30
  end

  describe 'asking for a suggestion' do
    it_behaves_like 'a bounded AI endpoint', 'agents/7/suggest', 30
  end

  describe 'copying a source' do
    it_behaves_like 'a bounded AI endpoint', 'agents/7/sources/copy', 10
  end

  it 'shares the builder budget across create, messages and retry' do
    20.times do
      %w[build_threads build_threads/7/messages build_threads/7/retry].each do |suffix|
        expect(rack_app.post("/api/v1/accounts/42/autonomia/#{suffix}", request_headers).status).to eq(200)
      end
    end

    expect(rack_app.post('/api/v1/accounts/42/autonomia/build_threads/7/retry', request_headers).status).to eq(429)
  end

  it 'cannot evade a web-token budget by changing UID or IP' do
    path = '/api/v1/accounts/42/autonomia/agents/7/test'
    headers = { 'REMOTE_ADDR' => '198.51.100.10', 'HTTP_ACCESS_TOKEN' => 'test-web-credential', 'HTTP_UID' => 'first-test-uid' }
    30.times { rack_app.post(path, headers) }

    changed = headers.merge('REMOTE_ADDR' => '198.51.100.11', 'HTTP_UID' => 'another-test-uid')
    expect(rack_app.post(path, changed).status).to eq(429)
  end

  it 'normalizes the supported extension and trailing slash into the same budget' do
    path = '/api/v1/accounts/42/autonomia/agents/7/test'
    30.times { rack_app.post(path, request_headers) }

    expect(rack_app.post("#{path}.json/", request_headers).status).to eq(429)
  end

  it 'uses the same account budget when its numeric ID has leading zeroes' do
    30.times { rack_app.post('/api/v1/accounts/42/autonomia/agents/7/test', request_headers) }

    expect(rack_app.post('/api/v1/accounts/0042/autonomia/agents/7/test', request_headers).status).to eq(429)
  end

  it 'uses the API credential when both API and web headers are present' do
    path = '/api/v1/accounts/42/autonomia/agents/7/test'
    headers = request_headers.merge('HTTP_ACCESS_TOKEN' => 'first-web-credential')
    30.times { rack_app.post(path, headers) }

    expect(rack_app.post(path, headers.merge('HTTP_ACCESS_TOKEN' => 'another-web-credential')).status).to eq(429)
  end

  it 'supports the existing unprefixed API credential header' do
    path = '/api/v1/accounts/42/autonomia/agents/7/test'
    headers = { 'REMOTE_ADDR' => '198.51.100.10', 'api_access_token' => api_token }
    30.times { rack_app.post(path, headers) }

    expect(rack_app.post(path, headers).status).to eq(429)
  end

  it 'keeps raw credentials and UID out of the cache and blocked-event log' do
    cache_keys = []
    logged_messages = []
    allow(cache_store).to receive(:increment).and_wrap_original do |original, key, *args, **options|
      cache_keys << key
      original.call(key, *args, **options)
    end
    allow(Rails.logger).to receive(:warn) { |message| logged_messages << message }
    headers = request_headers.merge('HTTP_UID' => 'private-test-uid')
    31.times { rack_app.post('/api/v1/accounts/42/autonomia/agents/7/test', headers) }

    expect(logged_messages).not_to be_empty
    expect(cache_keys.join).not_to include(api_token, 'private-test-uid')
    expect(logged_messages.join).not_to include(api_token, api_token[0..4], 'private-test-uid')
  end

  it 'allows the documented tester and guide burst under the defaults' do
    %w[build_threads build_threads/7/messages build_threads/7/retry agents/7/test agents/7/suggest agents/7/sources/copy].each do |suffix|
      5.times { expect(rack_app.post("/api/v1/accounts/42/autonomia/#{suffix}", request_headers).status).to eq(200) }
    end
  end
end
