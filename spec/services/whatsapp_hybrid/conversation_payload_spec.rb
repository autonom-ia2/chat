require 'rails_helper'

# chat#1067: o payload da conversa diz ao editor quando a próxima resposta sai pelo WhatsApp API.
describe 'WhatsApp API reply flag on the conversation payload', type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:allowed_ids) { account.id.to_s }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: allowed_ids) { example.run } }

  def create_ready_connection
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
      status_checked_at: Time.current
    )
  end

  def push_flag
    Conversations::EventDataPresenter.new(conversation).push_data[:whatsapp_api_reply]
  end

  def api_flag
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}",
        headers: administrator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['whatsapp_api_reply']
  end

  context 'when the official window is closed and the hybrid connection is ready' do
    before { create_ready_connection }

    it 'is true in the API payload and in the realtime event' do
      expect(api_flag).to be(true)
      expect(push_flag).to be(true)
    end
  end

  context 'when the official window is open' do
    before do
      create_ready_connection
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, account: account, inbox: inbox)
    end

    it 'is false because the reply goes through the Cloud' do
      expect(api_flag).to be(false)
      expect(push_flag).to be(false)
    end
  end

  context 'when there is no hybrid connection' do
    it 'is false' do
      expect(api_flag).to be(false)
      expect(push_flag).to be(false)
    end
  end

  context 'when the account is outside WHATSAPP_HYBRID_ACCOUNT_IDS' do
    let(:allowed_ids) { '' }

    before { create_ready_connection }

    it 'is false without looking up the hybrid connection' do
      allow(WhatsappHybrid::Connection).to receive(:find_by).and_call_original

      expect(api_flag).to be(false)
      expect(push_flag).to be(false)
      expect(WhatsappHybrid::Connection).not_to have_received(:find_by)
    end
  end

  context 'when the inbox is not WhatsApp' do
    let(:conversation) { create(:conversation, account: account) }

    it 'is false without looking up the hybrid connection' do
      allow(WhatsappHybrid::Connection).to receive(:find_by).and_call_original

      expect(api_flag).to be(false)
      expect(push_flag).to be(false)
      expect(WhatsappHybrid::Connection).not_to have_received(:find_by)
    end
  end
end
