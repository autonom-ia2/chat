require 'rails_helper'

# whatsapp_transport_outcome (chat#1349): resultado estável do envio pelo WhatsApp API, gravado em content_attributes.
# Quem decide reenviar por outro caminho (ex.: modelo da campanha no 131047) lê este campo em vez do texto do erro.
describe WhatsappHybrid::WebTransport do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
  let(:client) { instance_double(Waha::Client) }
  let(:agent) { create(:user, account: inbox.account) }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end
  let(:message) do
    create(:message, message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation,
                     account: inbox.account, inbox: inbox, sender: agent)
  end

  def outcome
    message.reload.content_attributes['whatsapp_transport_outcome']
  end

  def perform
    described_class.new(message: message, connection: connection, origin: 'human', client: client).perform
  end

  before do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511937016094@c.us' })
    allow(client).to receive(:new_message_id).and_return('3EB0AAAA')
    allow(client).to receive(:update_session)
    allow(client).to receive_messages(start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
  end

  it 'grava accepted quando o motor aceitou o envio' do
    allow(client).to receive(:send_text).and_return({ 'id' => 'true_5511937016094@c.us_3EB0AAAA' })

    perform

    expect(outcome).to eq('accepted')
    expect(message.status).not_to eq('failed')
  end

  it 'grava failed quando o WhatsApp bloqueia conversas novas (475)' do
    allow(client).to receive(:send_text).and_raise(Waha::Client::Error, 'WAHA POST /api/sendText -> 500: server returned error 475')
    allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } })
    allow(client).to receive(:capping).and_return({ 'cappingStatus' => 'CAPPED' })

    perform

    expect(outcome).to eq('failed')
    expect(message.status).to eq('failed')
  end

  it 'grava failed sem enviar quando o celular está desconectado' do
    connection.update!(status_checked_at: 5.minutes.ago)
    allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
    allow(client).to receive(:send_text)

    perform

    expect(client).not_to have_received(:send_text)
    expect(outcome).to eq('failed')
  end

  it 'grava failed quando o número do contato não tem WhatsApp' do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => false })
    allow(client).to receive(:send_text)

    perform

    expect(client).not_to have_received(:send_text)
    expect(outcome).to eq('failed')
  end

  it 'grava uncertain quando o motor não respondeu (pode ter saído)' do
    allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout, 'timeout')

    perform

    expect(outcome).to eq('uncertain')
    expect(message.status).to eq('failed')
  end

  it 'grava throttled, sem falhar a mensagem, quando o limite por minuto estourou' do
    allow(client).to receive(:send_text)
    allow_any_instance_of(WhatsappHybrid::RateLimit).to receive(:exceeded?).and_return(true) # rubocop:disable RSpec/AnyInstance

    expect { perform }.to have_enqueued_job(SendReplyJob).with(message.id)

    expect(client).not_to have_received(:send_text)
    expect(outcome).to eq('throttled')
    expect(message.status).not_to eq('failed')
  end

  it 'atualiza o resultado quando a nova tentativa depois do limite é aceita' do
    allow(client).to receive(:send_text).and_return({ 'id' => 'true_5511937016094@c.us_3EB0AAAA' })
    message.update!(content_attributes: { 'whatsapp_transport_outcome' => 'throttled' })

    perform

    expect(outcome).to eq('accepted')
  end
end
