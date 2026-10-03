require 'rails_helper'

RSpec.describe 'Instagram::DataDeletionsController', type: :request do
  let(:app_secret) { 'test-instagram-secret' }
  # Meta's signed_request carries the app-scoped id, which differs from the stored professional account id.
  let!(:channel) { create(:channel_instagram, app_scoped_user_id: 'app-scoped-123') }

  def encode(data)
    Base64.urlsafe_encode64(data, padding: false)
  end

  def signed_request_for(payload, secret = app_secret)
    encoded_payload = encode(payload.to_json)
    signature = encode(OpenSSL::HMAC.digest('SHA256', secret, encoded_payload))
    "#{signature}.#{encoded_payload}"
  end

  def payload_for(user_id)
    { 'algorithm' => 'HMAC-SHA256', 'issued_at' => Time.current.to_i, 'user_id' => user_id }
  end

  def post_signed(path, signed_request)
    with_modified_env INSTAGRAM_APP_SECRET: app_secret do
      post path, params: { signed_request: signed_request }
    end
  end

  before do
    InstallationConfig.where(name: %w[INSTAGRAM_APP_SECRET]).delete_all
    GlobalConfig.clear_cache
  end

  describe 'POST /instagram/deauthorize' do
    it 'flags the channel for reauthorization without deleting the token' do
      post_signed '/instagram/deauthorize', signed_request_for(payload_for(channel.app_scoped_user_id))

      expect(response).to have_http_status(:ok)
      expect(channel.reload.reauthorization_required?).to be true
      expect(channel[:access_token]).to be_present
    end

    it 'falls back to the professional account id for channels without an app-scoped id' do
      legacy_channel = create(:channel_instagram)

      post_signed '/instagram/deauthorize', signed_request_for(payload_for(legacy_channel.instagram_id))

      expect(response).to have_http_status(:ok)
      expect(legacy_channel.reload.reauthorization_required?).to be true
    end

    it 'returns ok when no channel matches the user' do
      post_signed '/instagram/deauthorize', signed_request_for(payload_for('unknown'))

      expect(response).to have_http_status(:ok)
    end

    it 'rejects a request signed with another secret' do
      post_signed '/instagram/deauthorize', signed_request_for(payload_for(channel.app_scoped_user_id), 'wrong-secret')

      expect(response).to have_http_status(:unauthorized)
      expect(channel.reload.reauthorization_required?).to be false
    end

    it 'rejects a malformed signed request' do
      post_signed '/instagram/deauthorize', 'not-a-signed-request'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /instagram/data_deletion' do
    it 'revokes the stored token and keeps the inbox and its conversations' do
      conversation = create(:conversation, inbox: channel.inbox, account: channel.account)

      post_signed '/instagram/data_deletion', signed_request_for(payload_for(channel.app_scoped_user_id))

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['confirmation_code']).to be_present
      expect(body['url']).to include('/instagram/data_deletion_status?code=')

      channel.reload
      expect(channel[:access_token]).to eq('')
      expect(channel.access_token).to be_nil
      expect(channel.reauthorization_required?).to be true
      expect(Conversation.exists?(conversation.id)).to be true
    end

    it 'returns a confirmation even when no channel matches the user' do
      post_signed '/instagram/data_deletion', signed_request_for(payload_for('unknown'))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['confirmation_code']).to be_present
    end

    it 'rejects a request signed with another secret' do
      post_signed '/instagram/data_deletion', signed_request_for(payload_for(channel.app_scoped_user_id), 'wrong-secret')

      expect(response).to have_http_status(:unauthorized)
      expect(channel.reload[:access_token]).to be_present
    end
  end

  describe 'GET /instagram/data_deletion_status' do
    it 'shows the deletion as completed for a code we issued' do
      post_signed '/instagram/data_deletion', signed_request_for(payload_for(channel.app_scoped_user_id))
      code = response.parsed_body['confirmation_code']

      get '/instagram/data_deletion_status', params: { code: code }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('completed')
    end

    it 'returns not found for an unknown code' do
      get '/instagram/data_deletion_status', params: { code: 'forged' }

      expect(response).to have_http_status(:not_found)
    end
  end
end
