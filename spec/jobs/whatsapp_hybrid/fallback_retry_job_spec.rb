require 'rails_helper'

# #1453: a nova tentativa do plano B do 131047 que ficou no limite por minuto. Só reenvia quem ainda está `throttled`.
RSpec.describe WhatsappHybrid::FallbackRetryJob, :aggregate_failures do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, account: account) }
  let(:client) { instance_double(Waha::Client) }
  let(:message) do
    create(:message, message_type: :outgoing, content: 'oi', conversation: conversation, account: account, inbox: inbox,
                     source_id: 'wamid.meta-1453',
                     content_attributes: { 'whatsapp_transport_fallback' => true, 'whatsapp_transport_outcome' => 'throttled' })
  end

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run } }

  before do
    WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-r1453', status: 'connected',
                                       connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
                                       status_checked_at: Time.current)
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0R1453', send_text: {}, start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-r1453:5511937016094')
  end

  it 'ainda throttled: reenvia pelo WhatsApp API, apesar do source_id da Meta' do
    described_class.perform_now(message.id)

    expect(client).to have_received(:send_text).once
    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('accepted')
  end

  # A trava de rajada (Message#prevent_message_flooding) roda em todo update!; a espera pelo limite por minuto não pode virar
  # falha só porque a conversa está em rajada.
  it 'conversa em rajada: assume a espera e reenvia, em vez de fechar a mensagem como falha' do
    message
    allow(Limits).to receive(:conversation_message_per_minute_limit).and_return(0)

    expect { described_class.perform_now(message.id) }.not_to raise_error

    expect(client).to have_received(:send_text).once
    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('accepted')
    expect(message).not_to be_failed
  end

  it 'erro inesperado no pedido de envio: pode ter saído, fica uncertain, e um job repetido não reenvia' do
    allow(client).to receive(:send_text).and_raise(RuntimeError, 'motor quebrou')

    expect { described_class.perform_now(message.id) }.to raise_error(RuntimeError, 'motor quebrou')
    described_class.perform_now(message.id)

    expect(client).to have_received(:send_text).once
    expect(message.reload).to be_failed
    expect(message.content_attributes['whatsapp_transport_outcome']).to eq('uncertain')
  end

  it 'erro antes do pedido ao motor: nada saiu, fica failed e a campanha manda o modelo' do
    campaign = create(:campaign, account: account, inbox: inbox, audience: [])
    delivery = CampaignFreeTextDelivery.create!(account: account, campaign: campaign, campaign_recipient_id: 1, inbox_id: inbox.id,
                                                source_id: 'wamid.meta-1453', message_id: message.id)
    allow(client).to receive(:new_message_id).and_raise(Redis::CannotConnectError)

    expect { described_class.perform_now(message.id) }
      .to raise_error(Redis::CannotConnectError)
      .and have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob).with(delivery.id)

    expect(client).not_to have_received(:send_text)
    expect(message.reload).to be_failed
    expect(message.content_attributes['whatsapp_transport_outcome']).to eq('failed')
  end

  it 'a conta saiu do WhatsApp API durante a espera: falha certa, sem envio, e a campanha manda o modelo' do
    campaign = create(:campaign, account: account, inbox: inbox, audience: [])
    delivery = CampaignFreeTextDelivery.create!(account: account, campaign: campaign, campaign_recipient_id: 1, inbox_id: inbox.id,
                                                source_id: 'wamid.meta-1453', message_id: message.id)

    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '') do
      expect { described_class.perform_now(message.id) }
        .to have_enqueued_job(CampaignJourney::ConversaAberta::QuedaJob).with(delivery.id)
    end

    expect(client).not_to have_received(:send_text)
    expect(message.reload).to be_failed
    expect(message.content_attributes['whatsapp_transport_outcome']).to eq('failed')
  end

  it 'outro resultado já gravado (job repetido): não reenvia' do
    message.update!(content_attributes: message.content_attributes.merge('whatsapp_transport_outcome' => 'accepted'))

    described_class.perform_now(message.id)

    expect(client).not_to have_received(:send_text)
  end
end
