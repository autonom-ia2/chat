require 'rails_helper'

RSpec.describe Google::CalendarAccessTokenService do
  let(:refresh_token) { SecureRandom.hex }
  let!(:channel) do
    create(
      :channel_email, :microsoft_email, provider_config: {
        expires_on: Time.zone.now - 3600,
        access_token: SecureRandom.hex,
        refresh_token: refresh_token
      }
    )
  end
  let(:new_access_token) { SecureRandom.hex }

  before do
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .with(body: { 'grant_type' => 'refresh_token', 'refresh_token' => refresh_token })
      .to_return(
        status: 200,
        body: { access_token: new_access_token, expires_at: (Time.zone.now + 3600).to_i, token_type: 'bearer' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'returns the refreshed access token and keeps the refresh token Google omits' do
    with_modified_env GOOGLE_OAUTH_CLIENT_ID: SecureRandom.uuid, GOOGLE_OAUTH_CLIENT_SECRET: SecureRandom.hex do
      expect(described_class.new(channel: channel).access_token).to eq(new_access_token)

      provider_config = channel.reload.provider_config
      expect(provider_config['access_token']).to eq(new_access_token)
      expect(provider_config['refresh_token']).to eq(refresh_token)
    end
  end
end
