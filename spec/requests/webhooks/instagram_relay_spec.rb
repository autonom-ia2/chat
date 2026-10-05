require 'rails_helper'

RSpec.describe 'Instagram webhook relay', type: :request do
  let(:app_secret) { 'test-instagram-secret' }
  let(:relay_url) { 'https://other-stack.example.com/webhooks/instagram' }

  def payload_for(recipient_id)
    {
      object: 'instagram',
      entry: [{ id: recipient_id, time: 1, messaging: [{ sender: { id: 'customer-1' }, recipient: { id: recipient_id },
                                                         timestamp: 1, message: { mid: 'mid-1', text: 'Oi' } }] }]
    }.to_json
  end

  def signature_for(body)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', app_secret, body)}"
  end

  def post_webhook(body, relay_urls: relay_url, headers: {})
    with_modified_env INSTAGRAM_APP_SECRET: app_secret, INSTAGRAM_WEBHOOK_RELAY_URLS: relay_urls do
      post '/webhooks/instagram', params: body,
                                  headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature_for(body) }.merge(headers)
    end
  end

  before do
    InstallationConfig.where(name: %w[INSTAGRAM_APP_SECRET INSTAGRAM_WEBHOOK_RELAY_URLS]).delete_all
    GlobalConfig.clear_cache
    allow(Webhooks::InstagramEventsJob).to receive(:perform_later)
    allow(Webhooks::InstagramRelayJob).to receive(:perform_later)
  end

  it 'relays events for an account not connected here with the original body and signature' do
    body = payload_for('unknown-ig-account')

    post_webhook(body)

    expect(response).to have_http_status(:success)
    expect(Webhooks::InstagramEventsJob).to have_received(:perform_later)
    expect(Webhooks::InstagramRelayJob).to have_received(:perform_later).with(relay_url, body, signature_for(body))
  end

  it 'relays to every configured stack' do
    second_url = 'https://third-stack.example.com/webhooks/instagram'

    post_webhook(payload_for('unknown-ig-account'), relay_urls: "#{relay_url}, #{second_url}")

    expect(Webhooks::InstagramRelayJob).to have_received(:perform_later).with(relay_url, anything, anything)
    expect(Webhooks::InstagramRelayJob).to have_received(:perform_later).with(second_url, anything, anything)
  end

  it 'does not relay events for an account connected here' do
    channel = create(:channel_instagram)

    post_webhook(payload_for(channel.instagram_id))

    expect(Webhooks::InstagramEventsJob).to have_received(:perform_later)
    expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
  end

  it 'never relays an event that was already relayed' do
    post_webhook(payload_for('unknown-ig-account'), headers: { Webhooks::InstagramRelayJob::RELAY_HEADER => '1' })

    expect(response).to have_http_status(:success)
    expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
  end

  it 'does not relay when no relay URL is configured' do
    post_webhook(payload_for('unknown-ig-account'), relay_urls: '')

    expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
  end

  it 'does not relay a request with an invalid signature' do
    with_modified_env INSTAGRAM_APP_SECRET: app_secret, INSTAGRAM_WEBHOOK_RELAY_URLS: relay_url do
      post '/webhooks/instagram', params: payload_for('unknown-ig-account'),
                                  headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => 'sha256=forged' }
    end

    expect(response).to have_http_status(:unauthorized)
    expect(Webhooks::InstagramRelayJob).not_to have_received(:perform_later)
  end
end
