require 'rails_helper'

# chat#1486: com o WhatsApp limitando conversas novas, o WhatsApp API só fala com quem o aparelho já conversou,
# e o erro 463 deixa o contato 6 h fora do WhatsApp API.
describe WhatsappHybrid::ReachOut do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:client) { instance_double(Waha::Client) }
  let(:agent) { create(:user, account: account) }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
      status_checked_at: Time.current
    )
  end
  let(:timelock) { WhatsappHybrid::Timelock.new(connection) }
  let(:reach_out) { described_class.new(connection, contact) }
  let(:ends_at) { Time.zone.parse('2026-10-14 00:26:00 UTC').to_i }

  around do |example|
    travel_to(Time.zone.parse('2026-10-13 18:20:00 UTC')) do
      with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: account.id.to_s) { example.run }
    end
  end

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0AAAA', start_typing: {}, stop_typing: {}, update_session: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
    Redis::Alfred.delete(timelock.key)
    Redis::Alfred.delete(reach_out.key)
  end

  def outgoing(attrs = {})
    create(:message, { message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation,
                       account: account, inbox: inbox, sender: agent }.merge(attrs))
  end

  def restrict!
    timelock.apply!('enforcementType' => 'RESTRICT_ALL_COMPANIONS', 'isActive' => true, 'timeEnforcementEnds' => ends_at)
  end

  def send_reply(message)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
  end

  context 'without any signal from WhatsApp' do
    it 'sends to a new contact through WhatsApp API as before' do
      allow(client).to receive(:send_text).and_return({})

      send_reply(outgoing)

      expect(client).to have_received(:send_text).once
      expect(reach_out.allowed?).to be(true)
    end
  end

  context 'when WhatsApp limits new conversations' do
    before { restrict! }

    it 'still sends through WhatsApp API to a contact the device already talked to' do
      outgoing(content_attributes: { whatsapp_transport: 'web' }, status: :delivered)
      allow(client).to receive(:send_text).and_return({})
      message = outgoing

      send_reply(message)

      expect(client).to have_received(:send_text).once
      expect(message.reload.status).not_to eq('failed')
    end

    it 'fails a new contact with the time in the account zone and never calls the engine' do
      account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' })
      allow(client).to receive(:send_text)
      message = outgoing

      send_reply(message)

      expect(client).not_to have_received(:send_text)
      expect(client).not_to have_received(:new_message_id)
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq('O WhatsApp limitou conversas novas por este número até 21:26. Use uma mensagem pronta.')
    end

    it 'does not count a failed or a Cloud message as a previous conversation' do
      outgoing(content_attributes: { whatsapp_transport: 'web' }, status: :failed)
      outgoing(status: :read)

      expect(reach_out.allowed?).to be(false)
    end

    it 'does not count what the device sent to another contact' do
      other = create(:contact, account: account, phone_number: '+5511900000000')
      other_conversation = create(:conversation, inbox: inbox, contact: other, account: account)
      create(:message, message_type: :outgoing, conversation: other_conversation, account: account, inbox: inbox,
                       content_attributes: { whatsapp_transport: 'web' })

      expect(reach_out.allowed?).to be(false)
    end

    it 'does not offer free text to a new contact: editor, CRM follow-up and booking notice fall back to a template' do
      router = WhatsappHybrid::Router.new(conversation)

      expect(router.web_ready?).to be(true)
      expect(router.web_reply_available?).to be(false)
      expect(conversation.can_reply?).to be(false)
      expect(Crm::FollowUps::MessagingWindow.new(conversation).hybrid_web_available?).to be(false)
    end

    it 'keeps offering free text to a contact the device already talked to' do
      outgoing(content_attributes: { whatsapp_transport: 'web' }, status: :delivered)

      expect(WhatsappHybrid::Router.new(conversation).web_reply_available?).to be(true)
      expect(conversation.can_reply?).to be(true)
      expect(Crm::FollowUps::MessagingWindow.new(conversation).hybrid_web_available?).to be(true)
    end

    it 'says "por enquanto" when the engine gave no end' do
      timelock.apply!('isActive' => true, 'timeEnforcementEnds' => nil)

      expect(reach_out.refusal_text).to eq(described_class::LIMITED_ERROR)
    end
  end

  context 'when the engine answers 463' do
    let(:engine_error) { 'WAHA POST /api/sendText -> 500: server returned error 463' }

    before do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Error, engine_error)
      allow(client).to receive(:timelock).and_return({ 'isActive' => true, 'timeEnforcementEnds' => ends_at })
    end

    it 'blocks the contact, does not resend, fails with a clear text and refreshes the limit outside the send' do
      message = outgoing

      expect { send_reply(message) }
        .to have_enqueued_job(WhatsappHybrid::TimelockRefreshJob).with(connection.id).on_queue('default').exactly(:once)

      expect(client).to have_received(:send_text).once
      expect(client).not_to have_received(:timelock)
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq(described_class::BLOCKED_ERROR)
      expect(reach_out.blocked?).to be(true)
      expect(Redis::Alfred.ttl(reach_out.key)).to be_within(5).of(6.hours.to_i)
    end

    it 'keeps the blocked contact out of WhatsApp API, even without a limit, until the block expires' do
      send_reply(outgoing)
      Redis::Alfred.delete(timelock.key)
      allow(client).to receive(:send_text).and_return({})

      later = outgoing
      send_reply(later)
      expect(client).to have_received(:send_text).once
      expect(later.reload.external_error).to start_with('O WhatsApp limitou conversas novas por este número até')

      Redis::Alfred.delete(reach_out.key)
      send_reply(outgoing)
      expect(client).to have_received(:send_text).twice
    end
  end
end
