require 'rails_helper'

RSpec.describe 'Webhooks::FacebookPageController', type: :request do
  let(:app_secret) { 'test-facebook-app-secret' }
  let(:page_id) { '1234567890' }
  let(:relay_url) { 'https://other-stack.example.com/bot' }
  let(:leadgen_value) { { 'leadgen_id' => '444', 'page_id' => page_id, 'form_id' => '555', 'created_time' => 1_761_000_000 } }
  let(:leadgen_body) do
    { object: 'page', entry: [{ id: page_id, time: 1_761_000_001, changes: [{ field: 'leadgen', value: leadgen_value }] }] }.to_json
  end
  let(:messaging) do
    { 'sender' => { 'id' => '999' }, 'recipient' => { 'id' => page_id }, 'timestamp' => 1_761_000_002,
      'message' => { 'mid' => 'm_1', 'text' => 'oi' } }
  end
  let(:messaging_body) { { object: 'page', entry: [{ id: page_id, time: 1_761_000_002, messaging: [messaging] }] }.to_json }
  let(:leadgen_job) { class_double(ApplicationJob, perform_later: true) }
  let(:feed_job) { class_double(ApplicationJob, perform_later: true) }

  def signature_for(body, secret = app_secret)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
  end

  def post_page_webhook(body, signature: signature_for(body), env: { FB_APP_SECRET: app_secret }, headers: {})
    with_modified_env env do
      post '/bot', params: body,
                   headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }.merge(headers)
    end
  end

  before do
    InstallationConfig.where(name: %w[FB_APP_SECRET WHATSAPP_APP_SECRET FB_PAGE_WEBHOOK_RELAY_URLS FB_VERIFY_TOKEN]).delete_all
    GlobalConfig.clear_cache
    stub_const('Webhooks::FacebookLeadgenJob', leadgen_job)
    stub_const('Webhooks::FacebookFeedJob', feed_job)
    allow(Facebook::Messenger::Bot).to receive(:receive)
    allow(Webhooks::InstagramRelayJob).to receive(:perform_later)
  end

  describe 'GET /bot' do
    it 'still answers the Meta verification through the messenger gem' do
      with_modified_env FB_VERIFY_TOKEN: 'verify-me' do
        get '/bot', params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => 'verify-me', 'hub.challenge' => '42' }
      end

      expect(response.body).to eq('42')
    end
  end

  describe 'POST /bot' do
    it 'enqueues the leadgen job with the page id, the raw change value and the entry time' do
      post_page_webhook(leadgen_body)

      expect(response).to have_http_status(:ok)
      expect(leadgen_job).to have_received(:perform_later).with(page_id, leadgen_value, 1_761_000_001)
      expect(Facebook::Messenger::Bot).not_to have_received(:receive)
    end

    it 'enqueues the feed job for feed changes' do
      value = { 'item' => 'comment', 'verb' => 'add', 'comment_id' => '1_2', 'post_id' => "#{page_id}_3" }
      body = { object: 'page', entry: [{ id: page_id, time: 10, changes: [{ field: 'feed', value: value }] }] }.to_json

      post_page_webhook(body)

      expect(feed_job).to have_received(:perform_later).with(page_id, value, 10)
      expect(leadgen_job).not_to have_received(:perform_later)
    end

    it 'passes the value through the job webhook_value when it has one, so the comment text stays out of Redis (#2197)' do
      slim_job = Class.new do
        def self.webhook_value(value) = value.except('message')
        def self.perform_later(*); end
      end
      stub_const('Webhooks::FacebookFeedJob', slim_job)
      allow(slim_job).to receive(:perform_later)
      value = { 'item' => 'comment', 'verb' => 'add', 'comment_id' => '1_2', 'message' => 'meu CPF é 123' }
      body = { object: 'page', entry: [{ id: page_id, time: 10, changes: [{ field: 'feed', value: value }] }] }.to_json

      post_page_webhook(body)

      expect(slim_job).to have_received(:perform_later).with(page_id, { 'item' => 'comment', 'verb' => 'add', 'comment_id' => '1_2' }, 10)
    end

    it 'accepts events signed with the WhatsApp app secret (same Meta app as the ads login)' do
      post_page_webhook(leadgen_body, signature: signature_for(leadgen_body, 'whatsapp-secret'),
                                      env: { WHATSAPP_APP_SECRET: 'whatsapp-secret' })

      expect(response).to have_http_status(:ok)
      expect(leadgen_job).to have_received(:perform_later)
    end

    it 'answers 200 and enqueues nothing for a field without a job' do
      body = { object: 'page', entry: [{ id: page_id, time: 10, changes: [{ field: 'ratings', value: {} }] }] }.to_json

      post_page_webhook(body)

      expect(response).to have_http_status(:ok)
      expect(leadgen_job).not_to have_received(:perform_later)
      expect(feed_job).not_to have_received(:perform_later)
    end

    it 'answers 200 when the consumer job is not deployed yet' do
      hide_const('Webhooks::FacebookLeadgenJob')

      post_page_webhook(leadgen_body)

      expect(response).to have_http_status(:ok)
    end

    it 'hands messaging events to the messenger gem handlers unchanged' do
      post_page_webhook(messaging_body)

      expect(response).to have_http_status(:ok)
      expect(Facebook::Messenger::Bot).to have_received(:receive).with(messaging)
    end

    it 'rejects an invalid signature without processing anything' do
      post_page_webhook(leadgen_body, signature: signature_for(leadgen_body, 'wrong-secret'))

      expect(response).to have_http_status(:unauthorized)
      expect(leadgen_job).not_to have_received(:perform_later)
      expect(Facebook::Messenger::Bot).not_to have_received(:receive)
    end

    it 'rejects a request without signature' do
      post_page_webhook(leadgen_body, signature: nil)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers 400 for a body that is not JSON' do
      post_page_webhook('not-json')

      expect(response).to have_http_status(:bad_request)
    end

    context 'when the relay to another stack is configured' do
      let(:env) { { FB_APP_SECRET: app_secret, FB_PAGE_WEBHOOK_RELAY_URLS: relay_url } }

      it 'relays every body with changes, with the original body and signature' do
        post_page_webhook(leadgen_body, env: env)

        expect(Webhooks::InstagramRelayJob).to have_received(:perform_later).with(relay_url, leadgen_body, signature_for(leadgen_body))
      end

      it 'relays messaging for a page that is not connected on this stack' do
        post_page_webhook(messaging_body, env: env)

        expect(Webhooks::InstagramRelayJob).to have_received(:perform_later).with(relay_url, messaging_body, signature_for(messaging_body))
      end

      it 'keeps messaging for a page connected on this stack' do
        create(:channel_facebook_page, page_id: page_id)

        post_page_webhook(messaging_body, env: env)

        expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
      end

      it 'never relays an event that was already relayed' do
        post_page_webhook(leadgen_body, env: env, headers: { Webhooks::InstagramRelayJob::RELAY_HEADER => '1' })

        expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
        expect(leadgen_job).to have_received(:perform_later)
      end

      it 'does not relay a request with an invalid signature' do
        post_page_webhook(leadgen_body, env: env, signature: signature_for(leadgen_body, 'wrong-secret'))

        expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
      end
    end
  end
end
