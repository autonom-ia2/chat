require 'rails_helper'

# Gravações do WhatsApp API DEPOIS que o motor aceitou (ou recusou) o envio: o resultado, o erro e o status. A validação
# `Message#prevent_message_flooding` roda em todo `update!` e recusa a gravação numa rajada. Se ela levantasse depois do
# envio, o job falharia com a mensagem já entregue (ou, na falha, o resultado não seria gravado e a tela mostraria
# "enviada" para o que não saiu). Estas gravações não podem depender dessa validação.
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

  def perform
    described_class.new(message: message, connection: connection, origin: 'human', client: client).perform
  end

  def flood!
    message # cria antes de ligar o limite
    allow(Limits).to receive(:conversation_message_per_minute_limit).and_return(0)
  end

  before do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511937016094@c.us' })
    allow(client).to receive(:new_message_id).and_return('3EB0AAAA')
    allow(client).to receive(:update_session)
    allow(client).to receive_messages(start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
  end

  it 'a trava de rajada recusa a validação da mensagem (premissa do cenário)' do
    flood!

    expect(message.reload).not_to be_valid
  end

  it 'grava accepted sem levantar quando a conversa está em rajada: o job não falha com a mensagem entregue' do
    allow(client).to receive(:send_text).and_return({ 'id' => 'true_5511937016094@c.us_3EB0AAAA' })
    flood!

    expect { perform }.not_to raise_error

    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('accepted')
    expect(client).to have_received(:send_text).once
  end

  it 'grava failed e o status failed numa rajada: a tela não fica "enviada" para o que não saiu' do
    allow(client).to receive(:send_text).and_raise(Waha::Client::Error, 'WAHA POST /api/sendText -> 500: server returned error 463')
    flood!

    expect { perform }.not_to raise_error

    expect(message.reload.status).to eq('failed')
    expect(message.content_attributes['whatsapp_transport_outcome']).to eq('failed')
  end

  it 'grava uncertain numa rajada quando o motor não respondeu: ninguém reenvia por cima' do
    allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout, 'sem resposta')
    flood!

    expect { perform }.not_to raise_error

    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('uncertain')
    expect(message.status).to eq('failed')
  end

  it 'grava throttled numa rajada e deixa a nova tentativa agendada' do
    allow(client).to receive(:send_text)
    allow_any_instance_of(WhatsappHybrid::RateLimit).to receive(:exceeded?).and_return(true) # rubocop:disable RSpec/AnyInstance
    flood!

    expect { perform }.not_to raise_error

    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('throttled')
    expect(client).not_to have_received(:send_text)
  end

  it 'o fechamento por erro inesperado também grava numa rajada' do
    flood!
    message.update_columns(content_attributes: { 'whatsapp_transport' => 'web' }) # rubocop:disable Rails/SkipsModelValidations

    outcome = WhatsappHybrid::UnexpectedErrorOutcome.settle!(message)

    expect(outcome).to eq('uncertain')
    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('uncertain')
  end
end
