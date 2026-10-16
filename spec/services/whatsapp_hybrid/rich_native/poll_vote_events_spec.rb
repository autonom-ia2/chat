require 'rails_helper'

# chat#1709 (fase 3): com a flag, a sessão do plano B assina `poll.vote` (gravar reinicia a sessão: nunca no envio), e o
# webhook do motor leva o voto à fila só com os campos usados.
describe WhatsappHybrid::RichNative::PollVoteEvents do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: channel.account, inbox: channel.inbox, session_name: 'hybrid-poll',
                                       status: 'connected', webhook_secret: 'segredo-de-teste')
  end
  let(:client) { instance_double(Waha::Client, create_session: {}, update_session: {}, capping: { 'cappingStatus' => 'NONE' }) }
  let(:assigner) { instance_double(WhatsappProxy::Assigner, enabled?: false) }
  let(:manager) { WhatsappHybrid::SessionManager.new(connection, client: client, proxy_assigner: assigner) }

  def remote(events)
    { 'status' => 'WORKING', 'config' => { 'webhooks' => [{ 'url' => connection.webhook_url, 'events' => events }] } }
  end

  it 'keeps the subscription of main without the flag' do
    allow(client).to receive(:get_session).and_return(remote(%w[session.status message.ack]))

    manager.refresh!

    expect(client).not_to have_received(:update_session)
  end

  it 'subscribes poll.vote with the flag on a refresh, but never while sending' do
    connection.account.enable_features!(Waha::RichNative::FLAG)
    allow(client).to receive(:get_session).and_return(remote(%w[session.status message.ack]))

    manager.refresh!(sync_proxy: false)
    expect(client).not_to have_received(:update_session)

    manager.refresh!
    expect(client).to have_received(:update_session)
      .with('hybrid-poll', config: hash_including('webhooks' => [hash_including('events' => %w[session.status message.ack poll.vote])]))
      .once
  end

  it 'does not write again once subscribed' do
    connection.account.enable_features!(Waha::RichNative::FLAG)
    allow(client).to receive(:get_session).and_return(remote(%w[session.status message.ack poll.vote]))

    manager.refresh!

    expect(client).not_to have_received(:update_session)
  end

  describe Webhooks::WhatsappHybridController, type: :request do
    let(:path) { "/webhooks/whatsapp_hybrid/#{connection.public_id}" }
    let(:body) do
      { id: "evt_#{SecureRandom.hex(8)}", timestamp: (Time.current.to_f * 1000).to_i, event: 'poll.vote', session: 'hybrid-poll',
        payload: { poll: { id: 'true_5511@c.us_3EB0POLL', to: '5511@c.us' },
                   vote: { id: 'V1', selectedOptions: ['Sim'], fromMe: false, timestamp: 1, from: '5511@c.us' } } }.to_json
    end

    def post_signed
      post path, params: body, headers: { 'CONTENT_TYPE' => 'application/json',
                                          'X-Webhook-Hmac' => OpenSSL::HMAC.hexdigest('SHA512', 'segredo-de-teste', body) }
    end

    it 'queues only the used fields of the vote with the flag' do
      connection.account.enable_features!(Waha::RichNative::FLAG)

      expect { post_signed }.to have_enqueued_job(WhatsappHybrid::RichNative::PollVoteJob)
        .with(connection.id, { 'poll_id' => 'true_5511@c.us_3EB0POLL', 'options' => ['Sim'], 'vote_id' => 'V1', 'from_me' => false })
      expect(response).to have_http_status(:ok)
    end

    it 'ignores the vote without the flag, as main ignores unknown events' do
      connection
      expect { post_signed }.not_to have_enqueued_job(WhatsappHybrid::RichNative::PollVoteJob)
      expect(response).to have_http_status(:ok)
    end
  end
end
