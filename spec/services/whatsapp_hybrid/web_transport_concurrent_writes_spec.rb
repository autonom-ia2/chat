require 'rails_helper'

# Eco da Meta e resultado do envio escrevem o mesmo content_attributes (chat#1555): quem escreve parte do registro RELIDO
# sob trava e acrescenta só as suas chaves; nunca devolve um hash lido antes.
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

  # O eco chega no meio do envio, depois de o WebTransport ter lido a mensagem (o objeto dele fica velho).
  def echo_arrives!
    fresh = Message.find(message.id)
    # Outro processo escreve direto na linha: o objeto do WebTransport não vê.
    fresh.update_columns(content_attributes: fresh.content_attributes.merge('whatsapp_web_id' => 'ECO1')) # rubocop:disable Rails/SkipsModelValidations
  end

  before do
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511937016094@c.us' })
    allow(client).to receive(:new_message_id).and_return('3EB0AAAA')
    allow(client).to receive(:update_session)
    allow(client).to receive_messages(start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
  end

  it 'mantém o whatsapp_web_id do eco ao gravar accepted' do
    allow(client).to receive(:send_text) do
      echo_arrives!
      { 'id' => 'true_5511937016094@c.us_3EB0AAAA' }
    end

    perform

    attrs = message.reload.content_attributes
    expect(attrs).to include('whatsapp_transport_outcome' => 'accepted', 'whatsapp_web_id' => 'ECO1', 'whatsapp_transport' => 'web')
  end

  it 'mantém o whatsapp_web_id do eco ao gravar a falha' do
    allow(client).to receive(:send_text) do
      echo_arrives!
      raise Waha::Client::Timeout, 'timeout'
    end

    perform

    attrs = message.reload.content_attributes
    expect(attrs).to include('whatsapp_transport_outcome' => 'uncertain', 'whatsapp_web_id' => 'ECO1')
    expect(message.status).to eq('failed')
  end

  it 'mantém o whatsapp_web_id do eco ao gravar throttled' do
    allow(client).to receive(:send_text)
    allow_any_instance_of(WhatsappHybrid::RateLimit).to receive(:exceeded?) do # rubocop:disable RSpec/AnyInstance
      echo_arrives!
      true
    end

    perform

    expect(message.reload.content_attributes).to include('whatsapp_transport_outcome' => 'throttled', 'whatsapp_web_id' => 'ECO1')
  end
end
