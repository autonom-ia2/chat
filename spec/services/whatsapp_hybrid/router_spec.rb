require 'rails_helper'

describe WhatsappHybrid::Router do
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
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current,
      status_checked_at: Time.current
    )
  end

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:check_contact_exists).and_return({ 'numberExists' => true, 'chatId' => '5511937016094@c.us' })
    allow(client).to receive(:new_message_id).and_return('3EB0AAAA')
    allow(client).to receive(:update_session)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
  end

  def outgoing(attrs = {})
    create(:message, { message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation,
                       account: inbox.account, inbox: inbox, sender: agent }.merge(attrs))
  end

  context 'when the official 24h window is closed' do
    it 'keeps the conversation replyable' do
      expect(conversation.can_reply?).to be(true)
    end

    it 'sends free text through WhatsApp API with the pre-generated id' do
      allow(client).to receive(:send_text).and_return({ 'id' => 'true_5511937016094@c.us_3EB0AAAA' })
      message = outgoing

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).to have_received(:send_text).with(session: 'hybrid-test', chat_id: '5511937016094@c.us',
                                                       text: 'Já tenho o retorno', id: '3EB0AAAA')
      expect(message.reload.source_id).to eq('3EB0AAAA')
      expect(message.content_attributes).to include('whatsapp_transport' => 'web', 'whatsapp_transport_origin' => 'human')
      expect(message.status).not_to eq('failed')
    end

    it 'marks an unconfirmed send as failed without retrying' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Timeout, 'timeout')
      message = outgoing

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('não confirmou')
      expect(client).to have_received(:send_text).once
    end

    it 'rechecks a stale session and refuses to send when the phone was disconnected' do
      connection.update!(status_checked_at: 5.minutes.ago)
      allow(client).to receive(:get_session).and_return({ 'status' => 'STOPPED' })
      allow(client).to receive(:send_text)
      message = outgoing

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).not_to have_received(:send_text)
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to include('desconectado')
      expect(connection.reload.status).to eq('disconnected')
      expect(conversation.reload.can_reply?).to be(false)
    end

    it 'explains the WhatsApp limit when new conversations are blocked' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Error, 'WAHA POST /api/sendText -> 500: server returned error 475')
      allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } })
      allow(client).to receive(:capping).and_return({ 'cappingStatus' => 'CAPPED' })
      message = outgoing

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.external_error).to include('limitou conversas novas')
    end

    it 'refreshes the session state when WhatsApp API rejects a send' do
      allow(client).to receive(:send_text).and_raise(Waha::Client::Error, '422')
      allow(client).to receive(:get_session).and_return({ 'status' => 'FAILED' })

      Whatsapp::SendOnWhatsappService.new(message: outgoing).perform

      expect(connection.reload.status).to eq('failed')
    end

    it 'falls back to the official failure when the risk was not accepted' do
      connection.update!(risk_accepted_at: nil)
      allow(client).to receive(:send_text)
      message = outgoing

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).not_to have_received(:send_text)
      expect(message.reload.status).to eq('failed')
      expect(conversation.reload.can_reply?).to be(false)
    end

    it 'never sends interactive Meta messages through WhatsApp API' do
      allow(client).to receive(:send_text)
      message = outgoing(content_type: :input_select, content_attributes: { items: [{ title: 'Sim', value: 'sim' }] })

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).not_to have_received(:send_text)
      expect(message.reload.status).to eq('failed')
    end

    it 'respects a disabled origin' do
      connection.update!(disabled_origins: ['human'])
      allow(client).to receive(:send_text)

      Whatsapp::SendOnWhatsappService.new(message: outgoing).perform

      expect(client).not_to have_received(:send_text)
    end

    it 'does not use WhatsApp API when the connected number is another one' do
      connection.update!(connected_phone: '5511000000000')

      expect(conversation.can_reply?).to be(false)
    end

    it 'does not use WhatsApp API for contacts without a phone number' do
      contact.update!(phone_number: nil)

      expect(conversation.reload.can_reply?).to be(false)
    end

    it 'waits for the next minute when the rate limit is reached' do
      connection.update!(rate_limit_per_minute: 1)
      allow(client).to receive(:send_text).and_return({})
      Whatsapp::SendOnWhatsappService.new(message: outgoing).perform

      second = outgoing
      expect { Whatsapp::SendOnWhatsappService.new(message: second).perform }.to have_enqueued_job(SendReplyJob).with(second.id)
      expect(client).to have_received(:send_text).once
    end

    it 'keeps the official window for accounts outside the pilot' do
      with_modified_env WHATSAPP_HYBRID_ACCOUNT_IDS: '' do
        expect(conversation.can_reply?).to be(false)
      end
    end

    it 'stays on the official path when the kill switch is off' do
      allow(client).to receive(:send_text)

      with_modified_env WHATSAPP_HYBRID_ROUTING_ENABLED: 'false' do
        Whatsapp::SendOnWhatsappService.new(message: outgoing).perform
      end

      expect(client).not_to have_received(:send_text)
    end
  end

  context 'when the official 24h window is open' do
    before { create(:message, message_type: :incoming, content: 'oi', conversation: conversation, account: inbox.account, inbox: inbox) }

    it 'sends through the Cloud as before' do
      allow(client).to receive(:send_text)
      allow(channel).to receive(:send_message).and_return('wamid.cloud')
      message = outgoing
      allow(message.conversation.inbox).to receive(:channel).and_return(channel)

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).not_to have_received(:send_text)
      expect(described_class.new(conversation).route_for(message)).to eq(:cloud)
    end
  end

  describe 'echo reconciliation' do
    let(:echo_wamid) { 'wamid.HBgTQlIuMTM3NzQ0NTI1NDIyMjE2MhUUABEYFjNFQjA2QjI0NjZFN0VGQkFCMkRFNzkA' }

    def echo_params
      {
        phone_number: channel.phone_number,
        object: 'whatsapp_business_account',
        entry: [{ changes: [{ field: 'smb_message_echoes', value: { message_echoes: [{
          from: channel.phone_number.delete('+'), to: '5511937016094', to_user_id: 'BR.1377445254222162',
          id: echo_wamid, text: { body: 'Já tenho o retorno' }, timestamp: Time.current.to_i.to_s, type: 'text'
        }] } }] }]
      }.with_indifferent_access
    end

    it 'updates the message sent through WhatsApp API instead of creating a second bubble' do
      message = outgoing(source_id: '3EB06B2466E7EFBAB2DE79')

      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: echo_params, outgoing_echo: true).perform
      end.not_to change(Message, :count)

      expect(message.reload.source_id).to eq(echo_wamid)
      expect(message.content_attributes['whatsapp_web_id']).to eq('3EB06B2466E7EFBAB2DE79')
    end

    it 'clears the failure when Meta proves an unconfirmed send went out' do
      message = outgoing(source_id: '3EB06B2466E7EFBAB2DE79', status: :failed, external_error: 'sem confirmação')

      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: echo_params, outgoing_echo: true).perform

      expect(message.reload.status).to eq('sent')
      expect(message.external_error).to be_nil
    end

    it 'keeps the original echo behaviour for messages sent from the phone' do
      expect do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: echo_params, outgoing_echo: true).perform
      end.to change(Message, :count).by(1)
    end
  end
end
