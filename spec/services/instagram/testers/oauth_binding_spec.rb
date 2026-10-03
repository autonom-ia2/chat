require 'rails_helper'

RSpec.describe Instagram::Testers::OauthBinding do
  let(:configuration) { instance_double(Instagram::Testers::Configuration, app_id: '10001', ensure_available!: nil) }
  let(:selection) { instance_double(Instagram::Testers::Selection) }
  let(:client) { instance_double(Instagram::Testers::Client) }
  let(:target) { { 'id' => '17841400000000001', 'username' => 'demo_company', 'app_id' => '10001' } }
  let(:payload) do
    { 'tester_selection' => target, 'sub' => 16, 'iat' => Time.current.to_i,
      'exp' => (15.minutes.from_now).to_i, 'jti' => SecureRandom.uuid }
  end

  before do
    allow(Instagram::Testers::Configuration).to receive(:new).with(account_id: 16).and_return(configuration)
    allow(Instagram::Testers::Selection).to receive(:new).with(account_id: 16, actor_id: 2, app_id: '10001').and_return(selection)
    allow(Instagram::Testers::RateLimiter).to receive(:check!)
    allow(Instagram::Testers::Client).to receive(:new).with(configuration: configuration).and_return(client)
    allow(selection).to receive(:verify).with('signed-synthetic-selection').and_return(target)
  end

  it 'rechecks acceptance before generating a bound OAuth state' do
    expect(client).to receive(:status).with(target['id']).and_return('accepted')
    expect(client).not_to receive(:invite)
    expect(described_class.prepare(token: 'signed-synthetic-selection', account_id: 16, actor_id: 2)).to eq(target)
  end

  %w[absent pending].each do |status|
    it "does not continue OAuth for #{status}" do
      allow(client).to receive(:status).and_return(status)
      expect { described_class.prepare(token: 'signed-synthetic-selection', account_id: 16, actor_id: 2) }
        .to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    end
  end

  it 'claims an expiring new state only once' do
    expect { described_class.claim!(payload) }.not_to raise_error
    expect { described_class.claim!(payload) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
  end

  it 'rejects wrong parent app, malformed selection and excessive lifetime' do
    target['app_id'] = '10002'
    expect { described_class.claim!(payload) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    target['app_id'] = '10001'
    payload['exp'] += 1
    expect { described_class.claim!(payload) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
    payload['exp'] -= 1
    target['id'] = 12_345
    expect { described_class.claim!(payload) }.to(raise_error { |error| expect(error.code).to eq('invalid_selection') })
  end
end
