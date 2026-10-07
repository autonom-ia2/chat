require 'rails_helper'

RSpec.describe 'WhatsApp Híbrido engine webhook', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-test',
                                       webhook_secret: 'segredo-de-teste')
  end
  let(:now_ms) { (Time.current.to_f * 1000).to_i }
  let(:body) do
    { id: "evt_#{SecureRandom.hex(8)}", timestamp: now_ms, event: 'session.status', session: 'hybrid-test',
      me: { id: '5511999993846@c.us', pushName: 'Loja' }, payload: { status: 'FAILED' } }.to_json
  end
  let(:path) { "/webhooks/whatsapp_hybrid/#{connection.public_id}" }

  def post_signed(payload, signature)
    post path, params: payload, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Webhook-Hmac' => signature }
  end

  it 'accepts a request signed with the connection secret' do
    signature = OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', body)

    expect { post_signed(body, signature) }
      .to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
      .with(connection.id, 'session.status', { 'status' => 'FAILED', 'me' => { 'id' => '5511999993846@c.us' } })
    expect(response).to have_http_status(:ok)
  end

  it 'applies a replayed event only once' do
    signature = OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', body)
    post_signed(body, signature)

    expect { post_signed(body, signature) }.not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:ok)
  end

  it 'refuses a signed event older than five minutes' do
    old = JSON.parse(body).merge('timestamp' => now_ms - 6.minutes.in_milliseconds).to_json

    expect { post_signed(old, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', old)) }
      .not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:bad_request)
  end

  it 'refuses a signed event without timestamp' do
    undated = JSON.parse(body).except('timestamp').to_json

    post_signed(undated, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', undated))

    expect(response).to have_http_status(:bad_request)
  end

  it 'accepts the signature in upper case hex' do
    post_signed(body, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', body).upcase)

    expect(response).to have_http_status(:ok)
  end

  it 'rejects a request without signature' do
    post path, params: body, headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a signed body that is not an object' do
    array_body = [1, 2].to_json

    post_signed(array_body, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', array_body))

    expect(response).to have_http_status(:bad_request)
  end

  it 'rejects a wrong signature' do
    expect { post_signed(body, 'assinatura-errada') }.not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers an unknown address exactly like a wrong signature' do
    post '/webhooks/whatsapp_hybrid/nao-existe', params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Webhook-Hmac' => 'x' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to be_empty
  end

  it 'refuses oversized bodies before anything else' do
    big = { id: 'evt_big', timestamp: now_ms, event: 'session.status', payload: { status: 'WORKING', pad: 'x' * 70_000 } }.to_json

    expect { post_signed(big, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', big)) }
      .not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:payload_too_large)
  end

  it 'ignores events other than session status and acks' do
    message_body = { id: 'evt_msg', timestamp: now_ms, event: 'message', payload: { body: 'oi' } }.to_json

    expect { post_signed(message_body, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', message_body)) }
      .not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:ok)
  end
end
