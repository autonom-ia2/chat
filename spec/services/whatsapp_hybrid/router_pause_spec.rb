require 'rails_helper'

# #1487: com o WhatsApp API pausado, a caixa se comporta como caixa sem Híbrido — tudo pela oficial.
describe WhatsappHybrid::Router do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
  let(:agent) { create(:user, account: inbox.account) }
  let(:router) { described_class.new(conversation) }
  let(:message) do
    create(:message, message_type: :outgoing, content: 'Oi', conversation: conversation, account: inbox.account,
                     inbox: inbox, sender: agent)
  end
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: inbox.account, inbox: inbox, session_name: 'hybrid-router-pause', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

  before do
    Redis::Alfred.delete(WhatsappHybrid::Timelock.new(connection).key)
    allow(router).to receive(:cloud_window_open?).and_return(false)
  end

  it 'picks WhatsApp API outside the 24h window before the pause (control)' do
    expect(router.route_for(message)).to eq(:web)
  end

  context 'when paused' do
    before { connection.update!(paused_at: Time.current) }

    it 'never picks WhatsApp API, even with the session still reported as connected' do
      expect(router.web_allowed_for?(message)).to be(false)
      expect(router.web_ready?).to be(false)
      expect(router.route_for(message)).to eq(:cloud)
    end

    it 'does not unlock free text in the editor nor report a reach-out refusal' do
      expect(router.web_reply_available?).to be(false)
      expect(router.reach_out_refused?(message)).to be(false)
    end

    it 'keeps the new conversation screen on templates only' do
      with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) do
        expect(WhatsappHybrid::NewConversation.new(inbox: inbox, contact: contact).free_text_available?).to be(false)
      end
    end
  end
end
