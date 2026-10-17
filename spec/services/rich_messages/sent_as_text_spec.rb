require 'rails_helper'

# chat#1555: quando um `rich_message` sai como TEXTO (WhatsApp Híbrido pelo WAHA, canal sem o formato ou caixa API),
# a mensagem guarda isso em `content_attributes`, no momento do envio, com o texto que o cliente recebeu:
#   rich_message_sent_as: 'text', rich_message_sent_text: '<corpo + versão em texto do tipo>'
describe 'Rich message sent as text' do # rubocop:disable RSpec/DescribeClass
  let(:link_button) { { 'type' => 'link_button', 'label' => 'Abrir', 'url' => 'https://exemplo.com.br/x' } }
  let(:sent_text) { "Já tenho o retorno\n\nAbrir: https://exemplo.com.br/x" }
  let(:marks) { { 'rich_message_sent_as' => 'text', 'rich_message_sent_text' => sent_text } }

  describe 'RichMessages.mark_sent_as_text!' do
    let(:message) do
      create(:message, message_type: :outgoing, content: 'Já tenho o retorno',
                       content_attributes: { rich_message: link_button, whatsapp_transport: 'web',
                                             whatsapp_transport_origin: 'human', whatsapp_transport_outcome: 'accepted' })
    end

    it 'records the format and the text the customer received, keeping the WhatsApp API keys (#1519)' do
      RichMessages.mark_sent_as_text!(message)

      expect(message.reload.content_attributes).to eq(
        'rich_message' => link_button, 'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => 'human',
        'whatsapp_transport_outcome' => 'accepted', **marks
      )
    end

    it 'keeps a whatsapp_web_id written by someone else between the read and the mark (echo from Meta)' do
      stale = Message.find(message.id)
      echo = Message.find(message.id)
      echo.update!(content_attributes: echo.content_attributes.merge('whatsapp_web_id' => '3EB0ECO'))

      RichMessages.mark_sent_as_text!(stale)

      expect(message.reload.content_attributes).to include('whatsapp_web_id' => '3EB0ECO', 'whatsapp_transport' => 'web', **marks)
    end

    it 'does not lock, query or update a message without rich_message (every Híbrido send goes through here)' do
      plain = create(:message, message_type: :outgoing, content: 'Oi', content_attributes: { whatsapp_transport: 'web' })
      allow(plain).to receive(:with_lock)
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { RichMessages.mark_sent_as_text!(plain) }

      expect(plain).not_to have_received(:with_lock)
      expect(queries).to be_empty
      expect(plain.reload.content_attributes).to eq('whatsapp_transport' => 'web')
    end

    it 'does not mark a message that failed' do
      message.update!(status: :failed)

      RichMessages.mark_sent_as_text!(message)

      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end

    it 'does not mark a type that is already text in every channel (link_preview)' do
      preview = create(:message, message_type: :outgoing, content: 'Veja https://exemplo.com.br',
                                 content_attributes: { rich_message: { type: 'link_preview' } })

      RichMessages.mark_sent_as_text!(preview)

      expect(preview.reload.content_attributes).to eq('rich_message' => { 'type' => 'link_preview' })
    end

    it 'never raises: logs only the error class and the message id, and leaves the message as it was' do
      allow(message).to receive(:with_lock).and_raise(ActiveRecord::Deadlocked, 'deadlock com dados')
      allow(Rails.logger).to receive(:error)

      expect { RichMessages.mark_sent_as_text!(message) }.not_to raise_error

      expect(Rails.logger).to have_received(:error).with("[rich_messages] mark_sent_as_text message=#{message.id} ActiveRecord::Deadlocked")
      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end
  end

  describe 'through the WhatsApp Híbrido (WAHA)' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
    let(:client) { instance_double(Waha::Client) }
    let!(:connection) do
      WhatsappHybrid::Connection.create!(
        account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
        connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
      )
    end

    def outgoing(content_attributes)
      create(:message, message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation, account: inbox.account,
                       inbox: inbox, sender: create(:user, account: inbox.account), content_attributes: content_attributes)
    end

    def send_by_web(message)
      WhatsappHybrid::WebTransport.new(message: message, connection: connection, origin: 'human', client: client).perform
    end

    before do
      allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                        new_message_id: '3EB0AAAA', send_text: { 'id' => 'true_5511937016094@c.us_3EB0AAAA' },
                                        start_typing: {}, stop_typing: {})
      allow(Kernel).to receive(:sleep)
      Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
    end

    it 'marks the message with the exact text sent, after it was accepted' do
      message = outgoing(rich_message: link_button)

      send_by_web(message)

      expect(client).to have_received(:send_text).with(hash_including(text: sent_text)).once
      expect(message.reload.content_attributes).to include('whatsapp_transport' => 'web', 'whatsapp_transport_outcome' => 'accepted', **marks)
    end

    it 'keeps the send accepted, without failing or resending, when the mark breaks' do
      message = outgoing(rich_message: link_button)
      # Quebra só a marca, por dentro dela: a trava (`with_lock`) que o envio usa para gravar o resultado fica intacta.
      allow(RichMessages).to receive(:sent_as_text_attributes).and_raise(ActiveRecord::Deadlocked)
      allow(Rails.logger).to receive(:error)
      allow(HTTParty).to receive(:post).and_call_original

      expect { send_by_web(message) }.not_to have_enqueued_job(SendReplyJob)

      expect(Rails.logger).to have_received(:error).with("[rich_messages] mark_sent_as_text message=#{message.id} ActiveRecord::Deadlocked")
      expect(client).to have_received(:send_text).once
      expect(message.reload.status).not_to eq('failed')
      expect(message.content_attributes).to include('whatsapp_transport_outcome' => 'accepted')
      expect(message.content_attributes).not_to have_key('external_error')
      expect(message.content_attributes).not_to have_key('rich_message_sent_as')
      # Nada saiu pela Cloud (o envio pela Meta usa HTTParty.post): o WAHA foi o único caminho, uma vez.
      expect(HTTParty).not_to have_received(:post)
    end

    it 'adds nothing to a message without rich_message' do
      message = outgoing({})

      send_by_web(message)

      expect(message.reload.content_attributes.keys).not_to include('rich_message_sent_as', 'rich_message_sent_text')
    end
  end

  describe 'through a channel without the format (360dialog)' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '123456789') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }
    let(:message) do
      create(:message, message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: link_button })
    end

    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account)
    end

    def send_reply(status, body = { 'messages' => [{ 'id' => 'd360' }] })
      stub_request(:post, 'https://waba.360dialog.io/v1/messages')
        .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      message.reload
    end

    it 'marks the message sent as text' do
      expect(send_reply(200).content_attributes).to include(marks)
    end

    it 'does not mark a message the channel refused' do
      sent = send_reply(400, { 'meta' => { 'success' => false, 'developer_message' => 'Recusado' } })

      expect(sent.status).to eq('failed')
      expect(sent.content_attributes).not_to have_key('rich_message_sent_as')
    end
  end

  describe 'on the official WhatsApp, with the window open' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: channel.inbox, contact_inbox: contact_inbox, account: channel.account) }

    it 'does not mark the message: it went out in the Meta format' do
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox, account: channel.account)
      stub_request(:post, 'https://graph.facebook.com/v22.0/123456789/messages')
        .to_return(status: 200, body: { messages: [{ id: 'wamid.rico' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      message = create(:message, message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation,
                                 inbox: channel.inbox, account: channel.account, content_attributes: { rich_message: link_button })

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(message.reload.source_id).to eq('wamid.rico')
      expect(message.content_attributes).not_to have_key('rich_message_sent_as')
    end
  end

  describe 'on an API inbox, whose webhook is the send' do
    let(:channel) { create(:channel_api, webhook_url: 'https://bridge.example.com/hook') }
    let(:conversation) { create(:conversation, inbox: channel.inbox, account: channel.account) }

    def create_outgoing(content_attributes, attrs = {})
      create(:message, { message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation, inbox: channel.inbox,
                         account: channel.account, content_attributes: content_attributes }.merge(attrs))
    end

    def dispatched_events
      events = []
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_wrap_original do |original, event, *args, **kwargs|
        events << event
        original.call(event, *args, **kwargs)
      end
      yield
      events
    end

    it 'is born marked, so the webhook delivers it once, without an extra message_updated' do
      message = nil
      events = dispatched_events { message = create_outgoing(rich_message: link_button) }

      expect(message.reload.content_attributes).to include(marks)
      expect(events).to include(Events::Types::MESSAGE_CREATED)
      expect(events).not_to include(Events::Types::MESSAGE_UPDATED)
    end

    it 'does not mark a rich_message that cannot go out (the webhook refuses it)' do
      message = create_outgoing(rich_message: link_button.merge('url' => 'exemplo.com.br'))

      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end

    it 'does not mark a private note, an inbox without webhook or a message without rich_message' do
      note = create_outgoing({ rich_message: link_button }, private: true)
      plain = create_outgoing({})
      channel.update!(webhook_url: '')
      no_webhook = create_outgoing(rich_message: link_button)

      [note, plain, no_webhook].each { |message| expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as') }
    end

    it 'does not mark a conversation whose broadcast is blocked: the webhook does not deliver it' do
      allow(Autonomia::Channels::BroadcastGuard).to receive(:blocked_conversation?).and_return(true)

      message = create_outgoing(rich_message: link_button)

      expect(Autonomia::Channels::BroadcastGuard).to have_received(:blocked_conversation?).with(conversation)
      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end

    it 'does not mark a link_preview, which is already text' do
      message = create_outgoing({ rich_message: { type: 'link_preview' } }, content: 'Veja https://exemplo.com.br')

      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end

    it 'costs nothing for a message without rich_message: no SQL and the inbox is not loaded' do
      plain = Message.new(inbox_id: channel.inbox.id, conversation_id: conversation.id, message_type: :outgoing, content: 'Oi')
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { RichMessages::ApiInboxSentAsText.before_create(plain) }

      expect(queries).to be_empty
      expect(plain.association(:inbox)).not_to be_loaded
      expect(plain.content_attributes).to eq({})
    end

    it 'does not break the creation when something inside it fails' do
      allow(RichMessages).to receive(:error_for).and_raise(ActiveRecord::ConnectionTimeoutError)

      message = nil
      expect { message = create_outgoing(rich_message: link_button) }.to change(Message, :count).by(1)
      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end

    it 'does not run outside an API inbox: elsewhere the mark is written by the send' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      whatsapp = create(:channel_whatsapp, sync_templates: false)
      other = create(:conversation, inbox: whatsapp.inbox, account: whatsapp.account)

      message = create(:message, message_type: :outgoing, content: 'Já tenho o retorno', conversation: other, inbox: whatsapp.inbox,
                                 account: whatsapp.account, content_attributes: { rich_message: link_button })

      expect(message.reload.content_attributes).not_to have_key('rich_message_sent_as')
    end
  end
end
