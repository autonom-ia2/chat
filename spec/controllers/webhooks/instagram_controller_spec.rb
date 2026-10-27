require 'rails_helper'

RSpec.describe 'Webhooks::InstagramController', type: :request do
  let(:client_secret) { 'test-instagram-secret' }

  def signature_for(body, secret = client_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  def post_instagram_webhook(body, signature: signature_for(body), env: { INSTAGRAM_APP_SECRET: client_secret })
    with_modified_env env do
      post '/webhooks/instagram',
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
    end
  end

  before do
    InstallationConfig.where(
      name: %w[FB_APP_SECRET IG_VERIFY_TOKEN INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN INSTAGRAM_WEBHOOK_RELAY_URLS]
    ).delete_all
    GlobalConfig.clear_cache
  end

  describe 'GET /webhooks/verify' do
    it 'returns 401 when valid params are not present' do
      get '/webhooks/instagram/verify'
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 when invalid params' do
      with_modified_env IG_VERIFY_TOKEN: '123456' do
        get '/webhooks/instagram/verify', params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => 'invalid' }
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'returns challenge when valid params' do
      with_modified_env IG_VERIFY_TOKEN: '123456' do
        get '/webhooks/instagram/verify', params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => '123456' }
        expect(response.body).to include '123456'
      end
    end
  end

  describe 'POST /webhooks/instagram' do
    let!(:dm_params) { build(:instagram_message_create_event).with_indifferent_access }
    let(:body) { dm_params.merge(object: 'instagram').to_json }

    it 'calls the instagram events job with the params for a valid signature' do
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)
      expect(Webhooks::InstagramEventsJob).to receive(:perform_later)

      post_instagram_webhook(body)
      expect(response).to have_http_status(:success)
    end

    it 'accepts webhook payloads signed with the Facebook app secret' do
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)
      expect(Webhooks::InstagramEventsJob).to receive(:perform_later)

      facebook_secret = 'test-facebook-secret'
      post_instagram_webhook(
        body,
        signature: signature_for(body, facebook_secret),
        env: { FB_APP_SECRET: facebook_secret }
      )

      expect(response).to have_http_status(:success)
    end

    it 'returns unauthorized when signature is missing' do
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)

      with_modified_env INSTAGRAM_APP_SECRET: client_secret do
        post '/webhooks/instagram',
             params: body,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::InstagramEventsJob).not_to have_received(:perform_later)
    end

    it 'returns unauthorized when signature is invalid' do
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)

      post_instagram_webhook(body, signature: 'sha256=invalid-signature')

      expect(response).to have_http_status(:unauthorized)
      expect(Webhooks::InstagramEventsJob).not_to have_received(:perform_later)
    end

    context 'when processing echo events' do
      let!(:echo_params) { build(:instagram_story_mention_event_with_echo).with_indifferent_access }
      let(:echo_body) { echo_params.merge(object: 'instagram').to_json }

      it 'delays processing for echo events by 2 seconds' do
        job_double = class_double(Webhooks::InstagramEventsJob)
        allow(Webhooks::InstagramEventsJob).to receive(:set).with(wait: 2.seconds).and_return(job_double)
        allow(job_double).to receive(:perform_later)

        post_instagram_webhook(echo_body)
        expect(response).to have_http_status(:success)
        expect(Webhooks::InstagramEventsJob).to have_received(:set).with(wait: 2.seconds)
        expect(job_double).to have_received(:perform_later)
      end
    end

    context 'when relaying to another stack (#2200)' do
      let(:relay_url) { 'https://other-stack.example.com/webhooks/instagram' }
      let(:comment_body) do
        { object: 'instagram',
          entry: [{ id: 'local-ig-1', time: 1, changes: [{ field: 'comments', value: { id: 'c1', text: 'oi' } }] }] }.to_json
      end

      before do
        allow(Webhooks::InstagramEventsJob).to receive(:perform_later)
        allow(Webhooks::InstagramRelayJob).to receive(:perform_later)
        create(:channel_instagram, instagram_id: 'local-ig-1')
      end

      it 'relays every body with changes, even for an account connected here' do
        post_instagram_webhook(comment_body, env: { INSTAGRAM_APP_SECRET: client_secret, INSTAGRAM_WEBHOOK_RELAY_URLS: relay_url })

        expect(Webhooks::InstagramRelayJob).to have_received(:perform_later).with(relay_url, comment_body, signature_for(comment_body))
      end

      it 'does not relay the dashboard test event (each stack would write it into one of its inboxes)' do
        test_body = { object: 'instagram', entry: [{ id: 'local-ig-1', time: 1, changes: [{ field: 'messages', value: { text: 'x' } }] }] }.to_json

        post_instagram_webhook(test_body, env: { INSTAGRAM_APP_SECRET: client_secret, INSTAGRAM_WEBHOOK_RELAY_URLS: relay_url })

        expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
      end

      it 'does not relay when no relay URL is configured' do
        post_instagram_webhook(comment_body)

        expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
      end

      it 'does not relay a body that was already relayed' do
        with_modified_env INSTAGRAM_APP_SECRET: client_secret, INSTAGRAM_WEBHOOK_RELAY_URLS: relay_url do
          post '/webhooks/instagram', params: comment_body,
                                      headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature_for(comment_body),
                                                 Webhooks::InstagramRelayJob::RELAY_HEADER => '1' }
        end

        expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
      end
    end
  end
end
