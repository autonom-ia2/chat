require 'spec_helper'
require_relative '../../../../config/environment'
require 'active_support/testing/time_helpers'

RSpec.describe Instagram::Automation::OperatorBrowserTicket do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 10, 5, 12) }
  let(:request_id) { SecureRandom.uuid }
  let(:control) { { 'id' => request_id, 'actor_id' => 42, 'state' => 'running', 'created_at' => (now - 120).iso8601(3) } }
  let(:hex_key) { 'ab' * 32 }
  let(:environment) do
    {
      'INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed', 'INSTAGRAM_TESTER_RUNTIME_STACK' => 'hub2you',
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL' => 'https://gateway.invalid/hub2you/',
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY' => hex_key, 'FRONTEND_URL' => 'https://hub.invalid/'
    }
  end

  around do |example|
    with_modified_env(environment) { travel_to(now) { example.run } }
  end

  it 'signs the exact claims using the decoded hex key and the existing JWT library' do
    grant = described_class.new.call(control: control, actor_id: 42)
    claims, header = JWT.decode(grant.fetch(:ticket), [hex_key].pack('H*'), true, algorithm: 'HS256')
    expect(header).to eq('typ' => 'JWT', 'alg' => 'HS256')
    expect(claims).to eq(
      'iss' => 'https://hub.invalid', 'aud' => 'instagram-operator-browser:hub2you', 'sub' => '42',
      'jti' => claims.fetch('jti'), 'iat' => now.to_i, 'exp' => now.to_i + 60, 'request_id' => request_id,
      'deadline' => now.to_i - 120 + 3600, 'stack' => 'hub2you'
    )
    expect(claims.fetch('jti')).to match(Instagram::Automation::OperatorControl::UUID)
    expect(grant.fetch(:grant_url)).to eq('https://gateway.invalid/hub2you/grant')
    expect(grant.fetch(:grant_url)).not_to include(grant.fetch(:ticket))
  end

  it 'issues a different nonce on each access and expires the ticket after sixty seconds' do
    ticket = described_class.new
    first = ticket.call(control: control, actor_id: 42).fetch(:ticket)
    second = ticket.call(control: control, actor_id: 42).fetch(:ticket)
    expect(JWT.decode(first, nil, false).first.fetch('jti')).not_to eq(JWT.decode(second, nil, false).first.fetch('jti'))
    travel 60.seconds
    expect { JWT.decode(first, [hex_key].pack('H*'), true, algorithm: 'HS256') }.to raise_error(JWT::ExpiredSignature)
  end

  it 'binds each stack to its own URL and audience' do
    with_modified_env('INSTAGRAM_TESTER_RUNTIME_STACK' => 'autonomia',
                      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL' => 'https://gateway.invalid/autonomia/') do
      grant = described_class.new.call(control: control, actor_id: 42)
      claims = JWT.decode(grant.fetch(:ticket), [hex_key].pack('H*'), true, algorithm: 'HS256').first
      expect(claims).to include('aud' => 'instagram-operator-browser:autonomia', 'stack' => 'autonomia')
      expect(grant.fetch(:grant_url)).to eq('https://gateway.invalid/autonomia/grant')
    end
  end

  it 'accepts only the current actor and the three active request states' do
    %w[queued running operator_required].each do |state|
      expect(described_class.eligible?(control: control.merge('state' => state), actor_id: 42)).to be(true)
    end
    [nil, control.merge('actor_id' => 43), control.merge('actor_id' => '42'),
     control.merge('state' => 'succeeded'), control.merge('state' => 'failed'),
     control.merge('created_at' => (now - 3600).iso8601)].each do |invalid|
      expect { described_class.new.call(control: invalid, actor_id: 42) }.to raise_error(described_class::Unavailable)
    end
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env') do
      expect { described_class.new.call(control: control, actor_id: 42) }.to raise_error(described_class::Unavailable)
    end
  end

  it 'rejects unsafe, incomplete or cross-stack configuration without disclosing it' do
    [
      ['INSTAGRAM_TESTER_RUNTIME_STACK', 'other'], ['INSTAGRAM_TESTER_RUNTIME_STACK', ''],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', 'a' * 63], ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', 'g' * 64],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', 'a' * 65], ['INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', ''],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'http://gateway.invalid/hub2you/'],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'https://user:synthetic@gateway.invalid/hub2you/'],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'https://gateway.invalid/hub2you/?ticket=synthetic'],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'https://gateway.invalid/hub2you/#synthetic'],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'https://gateway.invalid/autonomia/'],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'https://gateway.invalid/hub2you'],
      ['INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', 'invalid url'], ['FRONTEND_URL', 'http://hub.invalid'],
      ['FRONTEND_URL', 'https://user:synthetic@hub.invalid'], ['FRONTEND_URL', 'https://hub.invalid/?ticket=synthetic']
    ].each do |key, value|
      with_modified_env(key => value) do
        expect(described_class.configured?).to be(false)
        expect { described_class.new }.to raise_error(described_class::Unavailable, 'operator_browser_unavailable')
      end
    end
  end

  it 'does not read session secrets, publish, enqueue or contact remote services' do
    expect(Redis::SecureStorage).not_to receive(:get)
    expect(Instagram::Automation::SessionPublisher).not_to receive(:new)
    expect(Instagram::Automation::OperatorControl).not_to receive(:new)
    expect(Instagram::Testers::Client).not_to receive(:new)
    described_class.new.call(control: control, actor_id: 42)
  end
end
