require 'rails_helper'

RSpec.describe Crm::BookingV2::Tokens do
  let(:payload) { { 'p' => 42 } }

  it 'round-trips a payload for the same purpose' do
    token = described_class.generate('preview', payload, expires_in: 1.hour)

    expect(described_class.verify('preview', token)).to eq(payload)
  end

  it 'emits a URL-safe token (no / + or = characters)' do
    token = described_class.generate('form', payload, expires_in: 1.hour)

    expect(token.chars & %w[/ + =]).to be_empty
  end

  it 'refuses a token of one purpose in every other purpose' do
    described_class::PURPOSES.each do |purpose|
      token = described_class.generate(purpose, payload, expires_in: 1.hour)
      (described_class::PURPOSES - [purpose]).each do |other|
        expect(described_class.verify(other, token)).to be_nil, "#{purpose} token accepted as #{other}"
      end
    end
  end

  it 'refuses an expired token' do
    token = described_class.generate('preview', payload, expires_in: 1.hour)

    travel 61.minutes do
      expect(described_class.verify('preview', token)).to be_nil
    end
  end

  it 'refuses a tampered or garbage token' do
    token = described_class.generate('preview', payload, expires_in: 1.hour)
    raw = Base64.urlsafe_decode64(token)
    raw[0] = raw[0] == 'e' ? 'f' : 'e'
    tampered = Base64.urlsafe_encode64(raw, padding: false)

    expect(described_class.verify('preview', tampered)).to be_nil
    expect(described_class.verify('preview', 'not-a-token')).to be_nil
    expect(described_class.verify('preview', nil)).to be_nil
  end

  it 'encrypts the ics token: the payload is not readable and tampering is refused' do
    token = described_class.generate('ics', { 'c' => 'Xk4p9QaB' }, expires_in: 1.hour)
    raw = Base64.urlsafe_decode64(token)

    expect(described_class.verify('ics', token)).to eq('c' => 'Xk4p9QaB')
    expect(raw.split('--').map { |part| Base64.decode64(part) }.join).not_to include('Xk4p9QaB')
    raw[2] = raw[2] == 'A' ? 'B' : 'A'
    expect(described_class.verify('ics', Base64.urlsafe_encode64(raw, padding: false))).to be_nil
    travel 61.minutes do
      expect(described_class.verify('ics', token)).to be_nil
    end
  end

  it 'refuses a signed (not encrypted) ics token' do
    signed = Rails.application.message_verifier('crm_booking_v2_ics').generate({ 'c' => 'Xk4p9QaB' }, purpose: 'ics')

    expect(described_class.verify('ics', Base64.urlsafe_encode64(signed, padding: false))).to be_nil
  end

  it 'does not accept tokens from the v1 public booking verifier' do
    v1 = Rails.application.message_verifier('crm_public_booking').generate(payload)

    expect(described_class.verify('preview', Base64.urlsafe_encode64(v1, padding: false))).to be_nil
  end

  it 'raises on a purpose outside the closed list' do
    expect { described_class.generate('admin', payload, expires_in: 1.hour) }.to raise_error(described_class::UnknownPurpose)
    expect { described_class.verify('admin', 'x') }.to raise_error(described_class::UnknownPurpose)
  end
end
