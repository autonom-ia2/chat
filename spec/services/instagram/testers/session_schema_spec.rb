require 'rails_helper'

RSpec.describe Instagram::Testers::SessionSchema do
  let(:session) do
    {
      'cookie' => 'c_user=12345; xs=synthetic-session',
      'fb_dtsg' => 'synthetic-dtsg',
      'lsd' => 'synthetic-lsd',
      'jazoest' => '1234',
      'user_id' => '12345',
      'user_agent' => 'Synthetic Browser',
      'extra_form' => { '__req' => '1' }
    }
  end

  it 'accepts a browser session whose cookie identity matches user_id' do
    expect(described_class.valid?(session)).to be(true)
    expect(described_class.normalize(session)).to eq(session)
  end

  it 'allows synthetic preparation sessions only when identity is explicitly optional' do
    session['cookie'] = 'synthetic=fixture'

    expect(described_class.valid?(session)).to be(false)
    expect(described_class.valid?(session, require_identity: false)).to be(true)
  end

  it 'rejects a missing, duplicated, or mismatched c_user cookie' do
    [
      'xs=synthetic-session',
      'c_user=12345; c_user=12345',
      'c_user=99999; xs=synthetic-session'
    ].each do |cookie|
      session['cookie'] = cookie
      expect(described_class.valid?(session)).to be(false)
    end
  end

  it 'rejects unknown fields, control characters, and unsafe extra form fields' do
    expect(described_class.valid?(session.merge('endpoint' => 'https://example.com'))).to be(false)
    expect(described_class.valid?(session.merge('cookie' => "c_user=12345\nxs=bad"))).to be(false)
    expect(described_class.valid?(session.merge('extra_form' => { 'role' => 'admin' }))).to be(false)
  end

  it 'canonicalizes symbol keys without accepting duplicate string and symbol keys' do
    symbol_session = session.deep_symbolize_keys
    expect(described_class.normalize(symbol_session)).to include('user_id' => '12345')

    duplicate = session.merge(user_id: '99999')
    expect(described_class.valid?(duplicate)).to be(false)
  end

  it 'returns a deeply immutable canonical session' do
    normalized = described_class.normalize(session)

    expect(normalized).to be_frozen
    expect(normalized['extra_form']).to be_frozen
    expect { normalized['extra_form']['__req'] = '2' }.to raise_error(FrozenError)
  end
end
