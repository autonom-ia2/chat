require 'rails_helper'

RSpec.describe Autonomia::Connect::JwtVerifier do
  let(:key) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:kid) { 'connect-test-v1' }
  let(:issuer) { 'https://connect.example' }
  let(:audience) { 'https://agents.example/api/v1/autonomia/connect' }
  let(:jwk) { JSON.parse(JWT::JWK.new(key, kid: kid).export.to_json) }
  let(:verifier) do
    described_class.new(
      issuer: issuer,
      audience: audience,
      jwks_loader: -> { { 'keys' => [jwk] } }
    )
  end

  it 'accepts only a short-lived Connect provisioning token with the expected issuer, audience and scope' do
    token = signed_token

    expect(verifier.verify!("Bearer #{token}")).to include(
      'sub' => 'auth-user-123',
      'scope' => 'agents:provision',
      'client_id' => 'autonomia-connect'
    )
  end

  it 'rejects the wrong audience or scope' do
    expect do
      verifier.verify!("Bearer #{signed_token(aud: 'https://other.example')}")
    end.to raise_error(Autonomia::Connect::JwtVerifier::Unauthorized)

    expect do
      verifier.verify!("Bearer #{signed_token(scope: 'agents:provision agents:admin')}")
    end.to raise_error(Autonomia::Connect::JwtVerifier::Unauthorized)
  end

  def signed_token(aud: audience, scope: 'agents:provision', lifetime: 60)
    now = Time.current.to_i
    JWT.encode(
      {
        iss: issuer,
        sub: 'auth-user-123',
        aud: aud,
        scope: scope,
        client_id: 'autonomia-connect',
        iat: now,
        exp: now + lifetime,
        jti: SecureRandom.uuid
      },
      key,
      'ES256',
      kid: kid
    )
  end

  it 'rejects tokens issued for another client or an excessive lifetime' do
    token = signed_token
    payload, header = JWT.decode(token, nil, false)
    payload['client_id'] = 'other-client'
    wrong_client = JWT.encode(payload, key, 'ES256', kid: header['kid'])

    expect { verifier.verify!("Bearer #{wrong_client}") }.to raise_error(described_class::Unauthorized)
    expect { verifier.verify!("Bearer #{signed_token(lifetime: 300)}") }.to raise_error(described_class::Unauthorized)
  end
end
