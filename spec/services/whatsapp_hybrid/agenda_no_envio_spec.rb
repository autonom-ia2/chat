require 'rails_helper'

# #1865 — Híbrido: antes do "digitando" e do envio pelo WhatsApp API, o contato vai para a agenda do aparelho.
describe WhatsappHybrid::AgendaNoEnvio do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, name: 'Celmo Junior', phone_number: '+5521993735895') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5521993735895') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:client) { instance_double(Waha::Client) }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end
  let(:message) do
    create(:message, message_type: :outgoing, content: 'Oi', conversation: conversation, account: account, inbox: inbox,
                     sender: create(:user, account: account))
  end

  def perform
    WhatsappHybrid::WebTransport.new(message: message, connection: connection, origin: 'human', client: client).perform
  end

  before do
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '215349811278074@lid' },
                                      new_message_id: '3EB0AAAA', start_typing: {}, stop_typing: {},
                                      send_text: { 'id' => 'x' }, contact: { 'name' => '' }, upsert_contact: { 'success' => true })
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5521993735895')
    Redis::Alfred.delete('waha:agenda:hybrid-test:5521993735895@c.us')
  end

  it 'salva o contato pelo número (não pelo @lid do envio) antes de enviar' do
    account.enable_features!('whatsapp_agenda_do_contato')

    perform

    expect(client).to have_received(:upsert_contact)
      .with(session: 'hybrid-test', chat_id: '5521993735895@c.us', first_name: 'Celmo', last_name: 'Junior', timeout: 5).ordered
    expect(client).to have_received(:send_text).ordered
  end

  it 'sem a flag envia como antes, sem tocar na agenda' do
    perform

    expect(client).not_to have_received(:contact)
    expect(client).to have_received(:send_text)
  end

  it 'a falha da agenda não impede o envio' do
    account.enable_features!('whatsapp_agenda_do_contato')
    allow(client).to receive(:contact).and_raise(Waha::Client::Timeout, 'sem resposta')
    allow(Rails.logger).to receive(:info)

    perform

    expect(client).to have_received(:send_text)
    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('accepted')
  end
end
