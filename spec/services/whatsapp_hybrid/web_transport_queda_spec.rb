require 'rails_helper'

# #1453: o que o WebTransport grava quando o envio pode ter saído (nunca `failed`, para a campanha não mandar o modelo por
# cima), o teto do `throttled` e o aviso à campanha quando o texto que o Híbrido assumiu no 131047 falha de forma certa.
RSpec.describe WhatsappHybrid::WebTransport, :aggregate_failures do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, account: account) }
  let(:client) { instance_double(Waha::Client) }
  let(:connection) do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-q1453', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
  end
  let(:message) do
    create(:message, message_type: :outgoing, content: 'oi', conversation: conversation, account: account, inbox: inbox,
                     content_attributes: { 'whatsapp_transport_fallback' => true })
  end
  let(:session_manager) { instance_double(WhatsappHybrid::SessionManager, refresh!: true) }
  let(:transport) { described_class.new(message: message, connection: connection, origin: 'campaign', client: client) }

  before do
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0Q1453', send_text: {}, start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    allow(WhatsappHybrid::SessionManager).to receive(:new).and_return(session_manager)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-q1453:5511937016094')
    Redis::Alfred.delete("whatsapp_hybrid:throttle:#{message.id}")
  end

  def outcome
    message.reload.content_attributes['whatsapp_transport_outcome']
  end

  describe 'erro depois de o pedido de envio sair' do
    it '5xx do motor: incerto, nunca failed, e o estado da sessão é relido' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Error.new('WAHA POST /api/sendText -> 502: bad gateway', status: 502))

      transport.perform

      expect(outcome).to eq('uncertain')
      expect(session_manager).to have_received(:refresh!).with(sync_proxy: false)
    end

    it 'conexão fechada depois de enviar: incerto' do
      allow(client).to receive(:send_text).and_raise(Errno::ECONNRESET)

      transport.perform

      expect(outcome).to eq('uncertain')
    end

    it '475 e 463 continuam failed: o WhatsApp recusou, nada saiu' do
      allow(client).to receive(:send_text)
        .and_raise(Waha::Client::Error.new('WAHA POST /api/sendText -> 500: server returned error 475', status: 500))

      transport.perform

      expect(outcome).to eq('failed')
    end

    it '463 continua failed' do
      allow(client).to receive(:send_text)
        .and_raise(Waha::Client::Error.new('WAHA POST /api/sendText -> 500: server returned error 463', status: 500))

      transport.perform

      expect(outcome).to eq('failed')
    end

    it 'resposta 2xx ilegível no envio: incerto' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::InvalidResponse, 'WAHA POST /api/sendText resposta inválida')

      transport.perform

      expect(outcome).to eq('uncertain')
    end

    it 'resposta ilegível antes do envio (consulta do contato): failed, nada saiu' do
      allow(client).to receive(:check_contact_exists).and_raise(Waha::Client::InvalidResponse, 'WAHA GET resposta inválida')

      transport.perform

      expect(outcome).to eq('failed')
      expect(client).not_to have_received(:send_text)
    end

    it 'sem rota até o motor (EHOSTUNREACH) no envio: failed, nada saiu' do
      allow(client).to receive(:send_text).and_raise(Errno::EHOSTUNREACH)

      transport.perform

      expect(outcome).to eq('failed')
    end

    it 'ETIMEDOUT no envio: incerto' do
      allow(client).to receive(:send_text).and_raise(Errno::ETIMEDOUT)

      transport.perform

      expect(outcome).to eq('uncertain')
    end

    it 'sem resposta do motor ANTES do pedido de envio (consulta do contato): failed, nada saiu' do
      allow(client).to receive(:check_contact_exists).and_raise(Waha::Client::Timeout)

      transport.perform

      expect(outcome).to eq('failed')
      expect(message.reload.content_attributes['external_error']).to eq(described_class::NO_ANSWER_ERROR)
      expect(client).not_to have_received(:send_text)
    end

    it 'sem resposta ao pedido de envio: incerto, com o aviso de conferir no celular' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout)

      transport.perform

      expect(outcome).to eq('uncertain')
      expect(message.reload.content_attributes['external_error']).to eq(described_class::UNCONFIRMED_ERROR)
    end

    it '4xx do motor continua failed' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Error.new('WAHA POST /api/sendText -> 422: bad', status: 422))

      transport.perform

      expect(outcome).to eq('failed')
    end
  end

  describe 'teto do throttled' do
    let(:rate_limit) { instance_double(WhatsappHybrid::RateLimit, exceeded?: true) }

    before { allow(WhatsappHybrid::RateLimit).to receive(:new).and_return(rate_limit) }

    it 'mensagem do plano B do 131047 (tem o source_id da Meta): a nova tentativa vai pelo FallbackRetryJob' do
      expect { transport.perform }.to have_enqueued_job(WhatsappHybrid::FallbackRetryJob).with(message.id)
    end

    it 'nova tentativa que não entra na fila: falha certa, nunca fica throttled sem job' do
      allow(WhatsappHybrid::FallbackRetryJob).to receive(:set).and_raise(Redis::CannotConnectError)

      transport.perform

      expect(outcome).to eq('failed')
      expect(message.reload).to be_failed
      expect(message.content_attributes['external_error']).to eq(described_class::THROTTLE_ENQUEUE_ERROR)
    end

    it 'nova tentativa em voo não regrava throttled por cima de um resultado final' do
      message.update!(content_attributes: message.content_attributes.merge('whatsapp_transport_outcome' => 'failed'))

      transport.perform

      expect(outcome).to eq('failed')
    end

    it 'mensagem comum: sem teto, continua esperando pelo SendReplyJob' do
      message.update!(content_attributes: {})
      described_class::THROTTLE_MAX_RETRIES.times { transport.perform }

      expect { transport.perform }.to have_enqueued_job(SendReplyJob).with(message.id)
      expect(outcome).to eq('throttled')
      expect(message.reload).not_to be_failed
    end

    it 'mensagem comum: a nova tentativa continua pelo SendReplyJob' do
      message.update!(content_attributes: {})

      expect { transport.perform }.to have_enqueued_job(SendReplyJob).with(message.id)
    end

    it 'reagenda até o teto e depois falha de forma certa, sem reagendar' do
      described_class::THROTTLE_MAX_RETRIES.times { transport.perform }
      expect(outcome).to eq('throttled')

      expect { transport.perform }.not_to have_enqueued_job(WhatsappHybrid::FallbackRetryJob)
      expect(outcome).to eq('failed')
      expect(message.reload).to be_failed
    end
  end

  describe 'falha certa no texto de campanha que o Híbrido assumiu no 131047' do
    let(:campaign) { create(:campaign, account: account, inbox: inbox, audience: []) }

    def entrega(message_id: message.id, fell_back_at: nil)
      CampaignFreeTextDelivery.create!(account: account, campaign: campaign, campaign_recipient_id: 1, inbox_id: inbox.id,
                                       source_id: 'wamid.q1453', message_id: message_id, fell_back_at: fell_back_at)
    end

    before { allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => false }) }

    it 'pede o modelo da campanha' do
      delivery = entrega

      expect { transport.perform }.to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob).with(delivery.id)
    end

    it 'entrega que já caiu para o modelo: não pede de novo' do
      entrega(fell_back_at: Time.current)

      expect { transport.perform }.not_to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob)
    end

    it 'mensagem sem a marca do Híbrido (atendente, por exemplo): não pede modelo' do
      message.update!(content_attributes: {})
      entrega

      expect { transport.perform }.not_to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob)
    end

    it 'mensagem do plano B que não é de campanha (sem entrega): falha sem pedir modelo' do
      expect { transport.perform }.not_to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob)
      expect(outcome).to eq('failed')
    end

    it 'incerto não pede modelo' do
      allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511937016094@c.us' })
      allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout)
      entrega

      expect { transport.perform }.not_to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob)
    end
  end
end
