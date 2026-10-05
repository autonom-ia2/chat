require 'spec_helper'
require_relative '../../../../config/environment'

RSpec.describe Instagram::Automation::SessionStatus do
  subject(:status) { described_class.new.call }

  let(:namespace) { 'synthetic-status' }
  let(:version) { SecureRandom.uuid }
  let(:pointer_key) { "instagram_testers:session:#{namespace}:pointer" }
  let(:payload_key) { "instagram_testers:session:#{namespace}:payload:#{version}" }
  let(:captured_at) { '2026-10-05T12:00:00.000000Z' }
  let(:published_at) { '2026-10-05T12:01:00.000000Z' }
  let(:pointer) { { 'state' => 'active', 'version' => version, 'updated_at' => published_at, 'captured_at' => captured_at } }

  around { |example| with_modified_env('INSTAGRAM_TESTER_SESSION_NAMESPACE' => namespace) { example.run } }

  before do
    allow(Redis::Alfred).to receive(:get).with(pointer_key).and_return(pointer.to_json)
    allow(Redis::Alfred).to receive(:ttl).with(pointer_key).and_return(120)
    allow(Redis::Alfred).to receive(:ttl).with(payload_key).and_return(90)
    allow(Redis::Alfred).to receive(:exists?).with(payload_key).and_return(true)
    allow(Redis::SecureStorage).to receive(:get) { raise 'session_payload_read_forbidden' }
  end

  it 'returns capture/publication timestamps only from public pointer metadata' do
    expect(Redis::Alfred).not_to receive(:get).with(payload_key)
    expect(Redis::SecureStorage).not_to receive(:get)
    expect(status).to eq(state: 'active', present: true, ttl: 90, published_at: published_at, captured_at: captured_at)
    expect(status.to_json).not_to include(version)
  end

  it 'does not call invalidation time a publication time' do
    pointer.merge!('state' => 'invalidated', 'code' => 'http_401', 'invalidated_at' => published_at)
    allow(Redis::Alfred).to receive(:get).with(pointer_key).and_return(pointer.to_json)
    expect(status).to eq(state: 'invalidated', present: false, ttl: 120, captured_at: captured_at)
    expect(status.to_json).not_to include('http_401', version, 'published_at')
  end

  it 'preserves missing status for absent pointers, absent payloads and expired metadata' do
    allow(Redis::Alfred).to receive(:get).with(pointer_key).and_return(nil)
    expect(described_class.new.call).to eq(state: 'missing', present: false, ttl: nil)
    allow(Redis::Alfred).to receive(:get).with(pointer_key).and_return(pointer.to_json)
    allow(Redis::Alfred).to receive(:exists?).with(payload_key).and_return(false)
    expect(described_class.new.call).to eq(state: 'missing', present: false, ttl: nil)
    allow(Redis::Alfred).to receive(:exists?).with(payload_key).and_return(true)
    allow(Redis::Alfred).to receive(:ttl).with(payload_key).and_return(-2)
    expect(described_class.new.call).to eq(state: 'missing', present: false, ttl: nil)
  end

  it 'rejects malformed timestamps without reflecting arbitrary pointer data' do
    %w[updated_at captured_at].each do |field|
      allow(Redis::Alfred).to receive(:get).with(pointer_key).and_return(pointer.merge(field => 'synthetic-private-value').to_json)
      expect(described_class.new.call).to eq(state: 'invalid', present: false, ttl: nil)
    end
  end

  it 'preserves unavailable status without exposing Redis errors' do
    allow(Redis::Alfred).to receive(:get).with(pointer_key).and_raise(Redis::CannotConnectError, 'synthetic-private-value')
    expect(status).to eq(state: 'unavailable', present: false, ttl: nil)
  end
end
