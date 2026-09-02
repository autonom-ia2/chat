# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Sso::TokenStore do
  def build_token(**attributes)
    Autonomia::Sso::Client::Token.new(**attributes)
  end

  def fake_jwt(payload)
    header = { alg: 'none', typ: 'JWT' }
    [
      Base64.urlsafe_encode64(header.to_json, padding: false),
      Base64.urlsafe_encode64(payload.to_json, padding: false),
      'signature'
    ].join('.')
  end

  describe '.authorization_token_for' do
    it 'stores and returns the access token when Identity also returns an ID token' do
      user = create(:user)
      valid_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'sso-user-id',
        email: user.email
      )
      access_token = fake_jwt(token_use: 'access', sub: 'sso-user-id')
      id_token = fake_jwt(token_use: 'id', sub: 'sso-user-id')

      described_class.write!(
        valid_link,
        build_token(
          access_token: access_token,
          id_token: id_token,
          refresh_token: 'stored-refresh-token',
          expires_in: 3600
        )
      )

      expect(described_class.authorization_token_for(user)).to eq(access_token)
    end

    it 'uses the newest valid token when the user also has registration-only links' do
      user = create(:user)
      Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'registration-user-id',
        email: user.email,
        metadata: {
          'registration_checkout' => {
            'user_subscription_id' => 'subscription-123'
          }
        }
      )
      valid_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'sso-user-id',
        email: user.email,
        metadata: {
          'identity_user' => {
            'id' => 'sso-user-id',
            'email' => user.email
          }
        }
      )

      described_class.write!(valid_link, build_token(access_token: 'valid-access-token', expires_in: 3600))

      expect(described_class.authorization_token_for(user)).to eq('valid-access-token')
    end

    # The store only honours a positive expires_in (anything else falls back to
    # DEFAULT_TTL), so expiry is simulated by writing a real TTL and moving the
    # clock past it instead of passing a negative expires_in.
    it 'skips expired tokens without refresh tokens' do
      user = create(:user)
      expired_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'expired-sso-user-id',
        email: user.email
      )

      described_class.write!(expired_link, build_token(access_token: 'expired-access-token', expires_in: 3600))

      travel_to(2.hours.from_now) do
        expect(described_class.authorization_token_for(user)).to be_nil
      end
    end

    it 'refreshes expired tokens and returns the new access token' do
      user = create(:user)
      expired_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'refreshable-sso-user-id',
        email: user.email
      )
      client = instance_double(Autonomia::Sso::Client)
      refreshed_access_token = fake_jwt(token_use: 'access', sub: 'refreshable-sso-user-id')
      refreshed_id_token = fake_jwt(token_use: 'id', sub: 'refreshable-sso-user-id')

      described_class.write!(
        expired_link,
        build_token(
          access_token: 'expired-access-token',
          refresh_token: 'stored-refresh-token',
          expires_in: 3600
        )
      )

      allow(Autonomia::Sso::Client).to receive(:new).and_return(client)
      allow(client).to receive(:refresh_token!).with(refresh_token: 'stored-refresh-token').and_return(
        build_token(
          access_token: refreshed_access_token,
          id_token: refreshed_id_token,
          refresh_token: 'rotated-refresh-token',
          expires_in: 3600
        )
      )

      travel_to(2.hours.from_now) do
        expect(described_class.authorization_token_for(user)).to eq(refreshed_access_token)
        expect(client).to have_received(:refresh_token!).with(refresh_token: 'stored-refresh-token').once
        expect(described_class.authorization_token_for(user)).to eq(refreshed_access_token)
      end
    end

    it 'refreshes a valid legacy ID token immediately when a refresh token is available' do
      user = create(:user)
      legacy_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'legacy-sso-user-id',
        email: user.email
      )
      client = instance_double(Autonomia::Sso::Client)
      legacy_id_token = fake_jwt(token_use: 'id', sub: 'legacy-sso-user-id')
      refreshed_access_token = fake_jwt(token_use: 'access', sub: 'legacy-sso-user-id')

      described_class.write!(
        legacy_link,
        build_token(
          access_token: legacy_id_token,
          refresh_token: 'stored-refresh-token',
          expires_in: 3600
        )
      )

      allow(Autonomia::Sso::Client).to receive(:new).and_return(client)
      allow(client).to receive(:refresh_token!).with(refresh_token: 'stored-refresh-token').and_return(
        build_token(
          access_token: refreshed_access_token,
          refresh_token: 'rotated-refresh-token',
          expires_in: 3600
        )
      )

      expect(described_class.authorization_token_for(user)).to eq(refreshed_access_token)
    end

    it 'returns nil for a valid legacy ID token without a refresh token' do
      user = create(:user)
      legacy_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'legacy-sso-user-id',
        email: user.email
      )
      legacy_id_token = fake_jwt(token_use: 'id', sub: 'legacy-sso-user-id')

      described_class.write!(
        legacy_link,
        build_token(
          access_token: legacy_id_token,
          expires_in: 3600
        )
      )

      expect(described_class.authorization_token_for(user)).to be_nil
    end

    it 'does not reject opaque authorization tokens' do
      user = create(:user)
      valid_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'opaque-sso-user-id',
        email: user.email
      )

      described_class.write!(valid_link, build_token(access_token: 'opaque-access-token', expires_in: 3600))

      expect(described_class.authorization_token_for(user)).to eq('opaque-access-token')
    end

    it 'persists rotated refresh tokens' do
      user = create(:user)
      expired_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'refreshable-sso-user-id',
        email: user.email
      )
      client = instance_double(Autonomia::Sso::Client)

      described_class.write!(
        expired_link,
        build_token(
          access_token: 'expired-access-token',
          refresh_token: 'stored-refresh-token',
          expires_in: 3600
        )
      )

      allow(Autonomia::Sso::Client).to receive(:new).and_return(client)
      allow(client).to receive(:refresh_token!).and_return(
        build_token(
          access_token: 'refreshed-access-token',
          refresh_token: 'rotated-refresh-token',
          expires_in: 3600
        )
      )

      travel_to(2.hours.from_now) do
        described_class.authorization_token_for(user)
      end

      expect(described_class.new(expired_link.reload).send(:stored_refresh_token)).to eq('rotated-refresh-token')
    end
  end
end
