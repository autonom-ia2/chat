require 'rails_helper'

# chat#1709 (fase 1): no plano B do WhatsApp Híbrido, com a flag `whatsapp_rich_native`, a mensagem rica sai nativa.
describe WhatsappHybrid::RichNative do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:contact) { create(:contact, account: account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: account) }
  let(:client) { instance_double(Waha::Client) }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end
  let(:options) { { type: 'options', options: [{ id: 'manha', title: 'Manhã' }, { id: 'tarde', title: 'Tarde' }] } }

  around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

  before do
    allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                      new_message_id: '3EB0AAAA', send_text: { 'id' => 'true_5511937016094@c.us_3EB0AAAA' },
                                      start_typing: {}, stop_typing: {})
    allow(Kernel).to receive(:sleep)
    Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
    Redis::Alfred.delete(WhatsappHybrid::Config.inbox_flag_key(inbox.id))
  end

  def outgoing(rich_message, content: 'Qual horário fica melhor?')
    create(:message, message_type: :outgoing, content: content, conversation: conversation, account: account, inbox: inbox,
                     sender: create(:user, account: account), content_attributes: { rich_message: rich_message })
  end

  def send_by_web(message)
    WhatsappHybrid::WebTransport.new(message: message, connection: connection, origin: 'human', client: client).perform
  end

  def flag_on!
    account.enable_features!(described_class::FLAG)
  end

  describe 'sending through WhatsApp API' do
    it 'sends options as text, marked as text, while the flag is off (nothing changes)' do
      message = outgoing(options)

      send_by_web(message)

      expect(client).to have_received(:send_text).once
      expect(message.reload.content_attributes['rich_message_sent_as']).to eq('text')
    end

    it 'sends options as a native list, marks it native and keeps the id the engine gave for ack and echo' do
      flag_on!
      allow(client).to receive(:send_list).and_return({ 'id' => 'true_5511937016094@c.us_3EB0LIST' })
      message = outgoing(options)

      send_by_web(message)

      expect(client).not_to have_received(:send_text)
      expect(client).to have_received(:send_list).with(hash_including(session: 'hybrid-test', chat_id: '5511937016094@c.us')).once
      message.reload
      expect(message.source_id).to eq('3EB0LIST')
      expect(message.content_attributes).to include('rich_message_sent_as' => 'native', 'whatsapp_transport_outcome' => 'accepted')
      expect(message.content_attributes).not_to have_key('rich_message_sent_text')
      expect(WhatsappHybrid::WebTransport.message_for(connection, '3EB0LIST')).to eq(message)
    end

    # Resposta real do sendList no teste de 16/10/2026: `id` com `_serialized` terminando no id físico. O source_id e o
    # Redis guardam só o id curto, como o send_text (o id gerado, `3EB0...`), que é o que o ack do webhook procura
    # (WhatsappHybrid::WebhookEventJob: `payload['id'].split('_').last`).
    it 'keeps the short physical id of the real sendList answer, the same format the text send keeps' do
      flag_on!
      serialized = 'true_5511937016094@c.us_3EB0AD0AC2E780A4D758F5'
      allow(client).to receive(:send_list).and_return({ 'id' => { 'fromMe' => true, 'remote' => '5511937016094@c.us',
                                                                  'id' => '3EB0AD0AC2E780A4D758F5', '_serialized' => serialized } })
      text = create(:message, message_type: :outgoing, content: 'Oi', conversation: conversation, account: account, inbox: inbox,
                              sender: create(:user, account: account))
      send_by_web(text)
      list = outgoing(options)

      send_by_web(list)

      expect(text.reload.source_id).to eq('3EB0AAAA')
      expect(list.reload.source_id).to eq('3EB0AD0AC2E780A4D758F5')
      expect(WhatsappHybrid::WebTransport.message_for(connection, serialized.split('_').last)).to eq(list)
    end

    it 'sends a location natively with the pre-generated id in the source_id' do
      flag_on!
      allow(client).to receive(:send_location).and_return({})
      message = outgoing({ type: 'location', latitude: -23.5489, longitude: -46.6388, name: 'Unidade Centro' }, content: '')

      send_by_web(message)

      expect(client).to have_received(:send_location).with(hash_including(id: '3EB0AAAA', location: hash_including(title: 'Unidade Centro'))).once
      expect(message.reload.source_id).to eq('3EB0AAAA')
      expect(message.content_attributes['rich_message_sent_as']).to eq('native')
      expect(WhatsappHybrid::WebTransport.message_for(connection, '3EB0AAAA')).to eq(message)
    end

    it 'sends a contact card natively' do
      flag_on!
      allow(client).to receive(:send_contact_vcard).and_return(nil)
      message = outgoing({ type: 'contact', name: 'Recepção', phone: '+55 11 4000-0473' }, content: '')

      send_by_web(message)

      expect(client).to have_received(:send_contact_vcard).with(hash_including(id: '3EB0AAAA')).once
      expect(message.reload.content_attributes['rich_message_sent_as']).to eq('native')
    end

    it 'keeps a link button as text even with the flag on' do
      flag_on!
      message = outgoing({ type: 'link_button', label: 'Abrir', url: 'https://exemplo.com.br/x' })

      send_by_web(message)

      expect(client).to have_received(:send_text).once
      expect(message.reload.content_attributes['rich_message_sent_as']).to eq('text')
    end

    it 'falls back to text when the options do not fit the WhatsApp list' do
      flag_on!
      message = outgoing({ type: 'options', button: 'Um botão comprido demais', options: [{ id: 'a', title: 'A' }] })

      send_by_web(message)

      expect(client).to have_received(:send_text).once
      expect(message.reload.content_attributes['rich_message_sent_as']).to eq('text')
    end

    it 'fails like the text does when the engine refuses the native send, without a second send as text' do
      flag_on!
      allow(client).to receive(:send_list).and_raise(Waha::Client::Error.new('WAHA POST /api/sendList -> 400: bad', status: 400))
      allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } })
      allow(client).to receive(:update_session)
      allow(client).to receive(:capping).and_return({ 'cappingStatus' => 'NOT_CAPPED' })
      message = outgoing(options)

      send_by_web(message)

      expect(client).not_to have_received(:send_text)
      expect(message.reload.status).to eq('failed')
      expect(message.content_attributes['whatsapp_transport_outcome']).to eq('failed')
      expect(message.content_attributes).not_to have_key('rich_message_sent_as')
    end

    it 'keeps the send accepted when the native mark breaks (never a second send)' do
      flag_on!
      allow(client).to receive(:send_list).and_return({ 'id' => 'true_5511937016094@c.us_3EB0LIST' })
      allow(Redis::Alfred).to receive(:setex).and_call_original
      allow(Redis::Alfred).to receive(:setex).with("whatsapp_hybrid:msg:#{connection.id}:3EB0LIST", anything, anything)
                                             .and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:error)
      message = outgoing(options)

      send_by_web(message)

      expect(client).to have_received(:send_list).once
      expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('accepted')
      expect(Rails.logger).to have_received(:error).with("[whatsapp_hybrid] rich native mark message=#{message.id} Redis::CannotConnectError")
    end
  end

  describe 'RichMessages.delivery_mode' do
    it 'is native for options, location and contact in a hybrid inbox ready for the closed window, with the flag' do
      flag_on!

      %w[options location contact].each do |type|
        expect(RichMessages.delivery_mode(inbox: inbox, type: type, conversation: conversation)).to eq(:native)
      end
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'link_button', conversation: conversation)).to eq(:text)
    end

    it 'stays text without the flag, without a conversation, or with the session down' do
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:text)

      flag_on!
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options')).to eq(:text)

      connection.update!(status: 'disconnected')
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:text)
    end
  end

  describe '.types_for (campo whatsapp_api_rich_native da conversa)' do
    it 'lists the native types with the flag, outside the 24h window and with WhatsApp API ready' do
      flag_on!

      expect(described_class.types_for(conversation)).to eq(%w[options location contact])
    end

    it 'is empty without the flag' do
      expect(described_class.types_for(conversation)).to eq([])
    end

    it 'is empty inside the 24h window (the official sends the format itself)' do
      flag_on!
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: account)

      expect(described_class.types_for(conversation.reload)).to eq([])
    end

    it 'is empty with the connection paused' do
      flag_on!
      connection.update!(paused_at: Time.current)

      expect(described_class.types_for(conversation)).to eq([])
    end

    it 'is empty outside a hybrid inbox' do
      other = create(:conversation, account: account)
      flag_on!

      expect(described_class.types_for(other)).to eq([])
    end
  end

  describe 'linking the customer answer to the native list' do
    after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

    def native_list(ids)
      outgoing({ type: 'options', options: ids.map { |id| { id: id, title: id.capitalize } } }).tap do |message|
        message.update!(content_attributes: message.content_attributes.merge('rich_message_sent_as' => 'native',
                                                                             'whatsapp_transport' => 'web'))
      end
    end

    # O list_reply como chega pela oficial depois de uma lista mandada pelo aparelho: sem `context`.
    def receive_reply(id)
      params = {
        phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Camila' }, wa_id: '5511937016094' }],
          messages: [{ from: '5511937016094', id: "wamid.resposta-#{id}", timestamp: Time.current.to_i.to_s, type: 'interactive',
                       interactive: { type: 'list_reply', list_reply: { id: id, title: id.capitalize } } }]
        } }] }]
      }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
      inbox.messages.find_by!(source_id: "wamid.resposta-#{id}")
    end

    it 'links each answer to the latest native list that offered that exact id' do
      flag_on!
      morning = native_list(%w[manha tarde])
      units = native_list(%w[centro norte])

      expect(receive_reply('manha').content_attributes['in_reply_to']).to eq(morning.id)
      expect(receive_reply('norte').content_attributes['in_reply_to']).to eq(units.id)
    end

    # optionsAnswer.js compara `in_reply_to` com o id numérico da mensagem e lê `selected_option.id` em texto: o mesmo
    # formato que a oficial grava quando a resposta traz `context` (Whatsapp::InReplyToMessageFinder + SelectedOption).
    it 'writes in_reply_to as the numeric Chatwoot id and selected_option.id as a string, like the official path' do
      flag_on!
      offered = native_list(%w[manha tarde])

      reply = receive_reply('manha').reload

      expect(reply.content_attributes['in_reply_to']).to be_a(Integer).and eq(offered.id)
      expect(reply.content_attributes['selected_option']).to eq('id' => 'manha', 'title' => 'Manha')
      expect(reply.content_attributes['selected_option']['id']).to be_a(String)
      expect(reply.webhook_data[:content_attributes]).to include('in_reply_to' => offered.id)
    end

    it 'keeps the in_reply_to the official path wrote from context, without looking for a list' do
      flag_on!
      native_list(%w[manha])
      official = create(:message, message_type: :outgoing, conversation: conversation, inbox: inbox, account: account,
                                  content: 'Escolha', source_id: 'wamid.lista-oficial')
      params = {
        phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Camila' }, wa_id: '5511937016094' }],
          messages: [{ context: { from: channel.phone_number, id: 'wamid.lista-oficial' }, from: '5511937016094', id: 'wamid.com-contexto',
                       timestamp: Time.current.to_i.to_s, type: 'interactive',
                       interactive: { type: 'list_reply', list_reply: { id: 'manha', title: 'Manhã' } } }]
        } }] }]
      }.with_indifferent_access

      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform

      expect(inbox.messages.find_by!(source_id: 'wamid.com-contexto').content_attributes['in_reply_to']).to eq(official.id)
    end

    it 'picks the latest when two native lists offer the same id' do
      flag_on!
      native_list(%w[manha tarde])
      latest = native_list(%w[manha noite])

      expect(receive_reply('manha').content_attributes['in_reply_to']).to eq(latest.id)
    end

    it 'never matches by title, nor a list that went out as text, nor without the flag' do
      native_list(%w[manha])
      expect(receive_reply('manha').content_attributes).not_to have_key('in_reply_to')

      flag_on!
      text_list = outgoing({ type: 'options', options: [{ id: 'tarde', title: 'Tarde' }] })
      text_list.update!(content_attributes: text_list.content_attributes.merge('rich_message_sent_as' => 'text'))
      expect(receive_reply('tarde').content_attributes).not_to have_key('in_reply_to')
      expect(receive_reply('Manha').content_attributes).not_to have_key('in_reply_to')
    end
  end
end
