require 'rails_helper'

# chat#1457: a tela de nova conversa mostra o campo de texto quando o WhatsApp Híbrido pode enviar
# a primeira mensagem de um atendente; fora disso a caixa oficial continua só com modelo.
describe WhatsappHybrid::NewConversation, type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:allowed_ids) { account.id.to_s }
  let(:connection_attrs) { {} }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: allowed_ids) { example.run } }

  def create_connection
    WhatsappHybrid::Connection.create!(
      {
        account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
        connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
        status_checked_at: Time.current
      }.merge(connection_attrs)
    )
  end

  def service_flag
    described_class.new(inbox: inbox, contact: contact).free_text_available?
  end

  def api_flag
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
        headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    entry = response.parsed_body['payload'].find { |item| item['inbox']['id'] == inbox.id }
    entry['inbox']['whatsapp_api_start']
  end

  context 'when the hybrid connection is ready for human sends' do
    before { create_connection }

    it 'is true in the service and in the contactable inboxes payload' do
      expect(service_flag).to be(true)
      expect(api_flag).to be(true)
    end
  end

  context 'when there is no hybrid connection' do
    it 'is false' do
      expect(service_flag).to be(false)
      expect(api_flag).to be(false)
    end
  end

  context 'when the session is disconnected' do
    let(:connection_attrs) { { status: 'disconnected' } }

    before { create_connection }

    it('is false') { expect(service_flag).to be(false) }
  end

  context 'when routing is turned off on the connection' do
    let(:connection_attrs) { { routing_enabled: false } }

    before { create_connection }

    it('is false') { expect(service_flag).to be(false) }
  end

  context 'when the risk was not accepted' do
    let(:connection_attrs) { { risk_accepted_at: nil } }

    before { create_connection }

    it('is false') { expect(service_flag).to be(false) }
  end

  context 'when the human origin is disabled' do
    let(:connection_attrs) { { disabled_origins: ['human'] } }

    before { create_connection }

    it('is false') { expect(service_flag).to be(false) }
  end

  context 'when only other origins are disabled' do
    let(:connection_attrs) { { disabled_origins: %w[bot automation crm_follow_up campaign] } }

    before { create_connection }

    it('is true') { expect(service_flag).to be(true) }
  end

  context 'when the global kill switch is on' do
    before { create_connection }

    it 'is false' do
      with_modified_env(WHATSAPP_HYBRID_ROUTING_ENABLED: 'false') { expect(service_flag).to be(false) }
    end
  end

  context 'when the account is outside WHATSAPP_HYBRID_ACCOUNT_IDS' do
    let(:allowed_ids) { '' }

    before { create_connection }

    it 'is false without looking up the hybrid connection' do
      allow(WhatsappHybrid::Connection).to receive(:find_by).and_call_original

      expect(service_flag).to be(false)
      expect(WhatsappHybrid::Connection).not_to have_received(:find_by)
    end
  end

  context 'when the contact has no phone number' do
    let(:contact) { create(:contact, account: account, phone_number: nil, email: 'sem-telefone@example.com') }

    before { create_connection }

    it('is false') { expect(service_flag).to be(false) }
  end

  context 'when the inbox is not WhatsApp' do
    let(:inbox) { create(:inbox, account: account) }
    let(:account) { create(:account) }

    it('is false') { expect(service_flag).to be(false) }
  end

  # O servidor já manda pelo WhatsApp API o texto livre de uma conversa sem janela aberta.
  context 'when an agent sends the first free-text message of a new conversation' do
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
    let(:message) do
      create(:message, message_type: :outgoing, content: 'Olá', conversation: conversation, account: account, inbox: inbox,
                       sender: administrator)
    end

    before { create_connection }

    it 'routes it through the WhatsApp API transport' do
      expect(WhatsappHybrid::Router.new(conversation).route_for(message)).to eq(:web)
    end
  end
end
