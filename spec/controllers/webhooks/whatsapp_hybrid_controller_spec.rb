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

  it 'passes only the WhatsApp limit fields of the status event' do
    capped = JSON.parse(body).merge('payload' => { 'status' => 'WORKING', 'data' => { 'messageCapping' => {
                                      'cappingStatus' => 'CAPPED', 'totalQuota' => 1000, 'usedQuota' => 1000, 'mvStatus' => 'X'
                                    } } }).to_json

    expect { post_signed(capped, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', capped)) }
      .to have_enqueued_job(WhatsappHybrid::WebhookEventJob).with(
        connection.id, 'session.status',
        hash_including('capping' => { 'cappingStatus' => 'CAPPED', 'totalQuota' => 1000, 'usedQuota' => 1000 })
      )
  end

  it 'passes the new-conversations limit the engine sends in me.reachoutTimelock (chat#1486)' do
    limited = JSON.parse(body).merge('me' => { 'id' => '5511999993846@c.us', 'pushName' => 'Loja', 'reachoutTimelock' => {
                                       'enforcementType' => 'RESTRICT_ALL_COMPANIONS', 'isActive' => true,
                                       'timeEnforcementEnds' => 1_791_000_000, 'extra' => 'x'
                                     } }).to_json

    expect { post_signed(limited, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', limited)) }
      .to have_enqueued_job(WhatsappHybrid::WebhookEventJob).with(
        connection.id, 'session.status',
        { 'status' => 'FAILED', 'me' => { 'id' => '5511999993846@c.us' },
          'timelock' => { 'enforcementType' => 'RESTRICT_ALL_COMPANIONS', 'isActive' => true, 'timeEnforcementEnds' => 1_791_000_000 } }
      )
  end

  it 'passes fromMe, the physical id and only the device that read, never the phone (#2246)' do
    read = { id: 'evt_read', timestamp: now_ms, event: 'message.ack', session: 'hybrid-test',
             payload: { id: 'false_5511900000000@c.us_ABC123', from: '5511900000000@c.us', fromMe: false, ack: 3, ackName: 'READ',
                        _data: { Type: 'read', IsFromMe: true, MessageIDs: ['ABC123'], Sender: '5511999993846:0@s.whatsapp.net' } } }.to_json

    expect { post_signed(read, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', read)) }
      .to have_enqueued_job(WhatsappHybrid::WebhookEventJob).with(
        connection.id, 'message.ack',
        { 'ack' => 3, 'id' => 'ABC123', 'from_me' => false, 'aparelho' => '0' }
      )
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

  # #2246 do corpo assinado do GOWS até o "visto": controller (used_fields), job e serviço, sem double no meio.
  # Payload anonimizado, no formato derivado do código do motor (ainda não capturado em produção).
  describe 'read on the business phone, end to end (#2246)' do
    let(:physical_id) { '2A5D2D8DA089BE42E4D5' }
    let(:contact) { create(:contact, account: channel.account, phone_number: '+5511900000000') }
    let(:conversation) do
      create(:conversation, account: channel.account, inbox: channel.inbox, contact: contact, agent_last_seen_at: 1.hour.ago)
    end
    let!(:received) do
      create(:message, message_type: :incoming, conversation: conversation, account: channel.account, inbox: channel.inbox,
                       sender: contact, source_id: 'wamid.HBgNNTUxMTkzNzAxNjA5NBUCABIYFDJBNUQyRDhEQTA4OUJFNDJFNEQ1AA==')
    end

    def read_by(sender)
      { id: "evt_#{SecureRandom.hex(4)}", timestamp: now_ms, event: 'message.ack', session: 'hybrid-test',
        me: { id: '5511999993846@c.us' },
        payload: { id: "false_5511900000000@c.us_#{physical_id}", from: '5511900000000@c.us', fromMe: false, ack: 3,
                   ackName: 'READ', _data: { Type: 'read', IsFromMe: true, MessageIDs: [physical_id], Sender: sender } } }.to_json
    end

    def deliver_read(sender)
      read = read_by(sender)
      perform_enqueued_jobs(only: WhatsappHybrid::WebhookEventJob) do
        post_signed(read, OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', read))
      end
    end

    before do
      connection.update!(status: 'connected', connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current)
      Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(channel.inbox.id))
      channel.account.enable_features!(ConversaCanal::VistaNoCelular::FLAG)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
      WhatsappHybrid::LeituraNoCelular.indexar(received)
    end

    after { Redis::Alfred.delete(WhatsappHybrid::LeituraNoCelular.chave(channel.inbox.id, physical_id)) }

    it 'clears the unread dot when the main phone (device 0) read it' do
      deliver_read('5511999993846:0@s.whatsapp.net')

      expect(conversation.reload.unread_incoming_messages).to be_empty
    end

    it 'keeps the unread dot when a linked device (device 5) read it' do
      deliver_read('5511999993846:5@s.whatsapp.net')

      expect(conversation.reload.unread_incoming_messages).to contain_exactly(received)
    end
  end
end
