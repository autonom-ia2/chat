require 'rails_helper'

RSpec.describe 'WhatsApp Híbrido engine webhook', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-test',
                                       webhook_secret: 'segredo-de-teste')
  end
  let(:body) { { event: 'session.status', session: 'hybrid-test', payload: { status: 'FAILED' } }.to_json }
  let(:path) { "/webhooks/whatsapp_hybrid/#{connection.public_id}" }

  def post_signed(payload, signature)
    post path, params: payload, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Webhook-Hmac' => signature }
  end

  it 'accepts a request signed with the connection secret' do
    signature = OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', body)

    expect { post_signed(body, signature) }
      .to have_enqueued_job(WhatsappHybrid::WebhookEventJob).with(connection.id, 'session.status', hash_including('status' => 'FAILED'))
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a wrong signature' do
    expect { post_signed(body, 'assinatura-errada') }.not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'answers 404 for an unknown connection' do
    post '/webhooks/whatsapp_hybrid/nao-existe', params: body, headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:not_found)
  end

  it 'ignores events other than session status and acks' do
    message_body = { event: 'message', payload: { body: 'oi' } }.to_json

    expect { post_signed(message_body, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', message_body)) }
      .not_to have_enqueued_job(WhatsappHybrid::WebhookEventJob)
    expect(response).to have_http_status(:ok)
  end
end
