require 'rails_helper'
require_relative 'rich_native_context'

# chat#1709 (fase 1): o que a caixa híbrida promete (delivery_mode, campo da conversa) e a ligação da resposta à lista.
# O envio está em rich_native/transport_spec.rb.
describe WhatsappHybrid::RichNative do
  include_context 'with a hybrid inbox for rich native'

  describe 'RichMessages.delivery_mode' do
    def mode(type, message: nil, on: conversation)
      RichMessages.delivery_mode(inbox: inbox, type: type, conversation: on, message: message)
    end

    def draft(rich_message, content: 'Qual horário?', sender: nil)
      Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content_type: :text,
                  content: content, sender: sender, content_attributes: { rich_message: rich_message })
    end

    let(:location) { { type: 'location', latitude: -23.5, longitude: -46.6 } }

    it 'is native only for a message that the send would deliver natively (route and translator)' do
      flag_on!

      expect(mode('options', message: draft(options))).to eq(:native)
      expect(mode('location', message: draft(location, content: ''))).to eq(:native)
      expect(mode('options', message: draft(options, content: "Qual horário?\nResponda"))).to eq(:text)
      expect(mode('link_button', message: draft({ type: 'link_button', label: 'Abrir', url: 'https://exemplo.com.br' }))).to eq(:text)
    end

    # Sem a mensagem não há origem nem conteúdo: o modo de antes, sem presumir nada.
    it 'keeps the previous mode (text) for every type without a message' do
      flag_on!

      expect(%w[options location contact link_button].map { |type| mode(type) }).to eq(%i[text text text text])
    end

    it 'follows the send route: text without the flag, without a conversation, with the origin off or the session down' do
      agent = create(:user, account: account)
      expect(mode('location', message: draft(location, content: '', sender: agent))).to eq(:text)

      flag_on!
      expect(mode('location', message: draft(location, content: '', sender: agent), on: nil)).to eq(:text)

      connection.update!(disabled_origins: ['human'])
      expect(mode('location', message: draft(location, content: '', sender: agent))).to eq(:text)
      expect(mode('location', message: draft(location, content: ''))).to eq(:native)

      connection.update!(disabled_origins: [], status: 'disconnected')
      expect(mode('location', message: draft(location, content: '', sender: agent))).to eq(:text)
    end
  end

  describe 'Waha::RichNative.types_for (campo whatsapp_api_rich_native da conversa)' do
    it 'lists the native types with the flag, outside the 24h window and with WhatsApp API ready' do
      flag_on!

      expect(Waha::RichNative.types_for(conversation)).to eq(%w[options location contact])
      expect(Waha::RichNative.types_for(conversation, api_reply: true)).to eq(%w[options location contact])
    end

    it 'is empty without the flag' do
      expect(Waha::RichNative.types_for(conversation)).to eq([])
    end

    it 'is empty inside the 24h window (the official sends the format itself)' do
      flag_on!
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: account)

      expect(Waha::RichNative.types_for(conversation.reload)).to eq([])
    end

    it 'is empty with the connection paused' do
      flag_on!
      connection.update!(paused_at: Time.current)

      expect(Waha::RichNative.types_for(conversation)).to eq([])
    end

    it 'is empty outside a hybrid inbox' do
      other = create(:conversation, account: account)
      flag_on!

      expect(Waha::RichNative.types_for(other)).to eq([])
    end

    it 'reuses the whatsapp_api_reply the caller already has instead of asking the router again' do
      flag_on!
      conversation
      allow(WhatsappHybrid::Router).to receive(:new).and_call_original

      expect(Waha::RichNative.types_for(conversation, api_reply: false)).to eq([])
      expect(Waha::RichNative.types_for(conversation, api_reply: true)).to eq(%w[options location contact])
      expect(WhatsappHybrid::Router).not_to have_received(:new)
    end

    # Como na lista de conversas de um request: `Current.account` é a conta da rota, e a caixa vem carregada.
    [true, false].each do |flag|
      it "adds no query for hybrid conversations outside the window with the flag #{flag ? 'on' : 'off'}" do
        flag_on! if flag
        hybrid = Array.new(3) do |index|
          contact = create(:contact, account: account, phone_number: "+55119370160#{index}0")
          create(:conversation, account: account, inbox: inbox, contact: contact,
                                contact_inbox: create(:contact_inbox, inbox: inbox, contact: contact, source_id: "55119370160#{index}0"))
        end
        loaded = Conversation.where(id: hybrid.map(&:id)).includes(:inbox).to_a
        replies = loaded.map(&:whatsapp_api_reply?)
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }
        Current.account = Account.find(account.id)

        result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          loaded.zip(replies).map { |item, reply| Waha::RichNative.types_for(item, api_reply: reply) }
        end

        expect(replies).to all(be(true))
        expect(result).to all(eq(flag ? %w[options location contact] : []))
        expect(queries).to be_empty
      ensure
        Current.reset
      end
    end

    it 'adds no query for a list of ordinary conversations with the flag off' do
      conversations = Array.new(3) { create(:conversation, account: account) }
      loaded = Conversation.where(id: conversations.map(&:id)).includes(:inbox).to_a
      replies = loaded.map(&:whatsapp_api_reply?)
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        loaded.zip(replies).each { |item, reply| Waha::RichNative.types_for(item, api_reply: reply) }
      end

      expect(queries).to be_empty
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

    def webhook(row_id, wamid, context: nil)
      {
        phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Camila' }, wa_id: '5511937016094' }],
          messages: [{ context: context, from: '5511937016094', id: wamid, timestamp: Time.current.to_i.to_s, type: 'interactive',
                       interactive: { type: 'list_reply', list_reply: { id: row_id, title: 'Manhã' } } }.compact]
        } }] }]
      }.with_indifferent_access
    end

    # O list_reply como chega pela oficial depois de uma lista mandada pelo aparelho: sem `context`, com o `rowId` inteiro.
    def receive_reply(row_id, context: nil)
      wamid = "wamid.resposta-#{SecureRandom.hex(4)}"
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: webhook(row_id, wamid, context: context)).perform
      inbox.messages.find_by!(source_id: wamid).reload
    end

    it 'links to the list in the rowId reference, even with a newer list offering the same option, and keeps the original id' do
      flag_on!
      old = native_list(%w[manha tarde])
      new = native_list(%w[manha noite])

      reply_old = receive_reply("manha|#{old.id}")
      reply_new = receive_reply("manha|#{new.id}")

      expect(reply_old.content_attributes['in_reply_to']).to eq(old.id)
      expect(reply_new.content_attributes['in_reply_to']).to eq(new.id)
      expect(reply_old.content_attributes['selected_option']).to eq('id' => 'manha', 'title' => 'Manhã')
    end

    # optionsAnswer.js compara `in_reply_to` com o id numérico da mensagem e lê `selected_option.id` em texto: o mesmo
    # formato que a oficial grava quando a resposta traz `context` (Whatsapp::InReplyToMessageFinder + SelectedOption).
    it 'writes in_reply_to as the numeric Chatwoot id and selected_option.id as a string, like the official path' do
      flag_on!
      offered = native_list(%w[manha tarde])

      reply = receive_reply("manha|#{offered.id}")

      expect(reply.content_attributes['in_reply_to']).to be_a(Integer).and eq(offered.id)
      expect(reply.content_attributes['selected_option']['id']).to be_a(String).and eq('manha')
      expect(reply.webhook_data[:content_attributes])
        .to include('in_reply_to' => offered.id, 'selected_option' => { 'id' => 'manha', 'title' => 'Manhã' })
    end

    it 'drops a reference that does not match (other conversation, not a native list) and searches by the option id' do
      flag_on!
      latest = native_list(%w[manha])
      foreign = create(:message, message_type: :outgoing, account: account, inbox: inbox, content: 'x',
                                 conversation: create(:conversation, account: account, inbox: inbox))
      text_list = outgoing({ type: 'options', options: [{ id: 'manha', title: 'Manhã' }] })

      [foreign.id, text_list.id].each do |reference|
        reply = receive_reply("manha|#{reference}")
        expect(reply.content_attributes['in_reply_to']).to eq(latest.id)
        expect(reply.content_attributes['selected_option']).to eq('id' => 'manha', 'title' => 'Manhã')
      end
    end

    it 'keeps the original option id when the customer taps a list of a PREVIOUS conversation' do
      flag_on!
      old_list = native_list(%w[manha tarde])
      conversation.update!(status: :resolved)

      reply = receive_reply("manha|#{old_list.id}")

      expect(reply.conversation_id).not_to eq(conversation.id)
      expect(reply.content_attributes['selected_option']).to eq('id' => 'manha', 'title' => 'Manhã')
      expect(reply.content_attributes['in_reply_to']).to be_blank
    end

    it 'does not split an option id that has the separator itself (it goes without reference)' do
      flag_on!
      offered = native_list(['plano|2024'])

      reply = receive_reply('plano|2024')

      expect(reply.content_attributes['in_reply_to']).to eq(offered.id)
      expect(reply.content_attributes['selected_option']['id']).to eq('plano|2024')
    end

    it 'uses the reference even with the flag turned off after the send' do
      offered = native_list(%w[manha])

      reply = receive_reply("manha|#{offered.id}")

      expect(reply.content_attributes['in_reply_to']).to eq(offered.id)
      expect(reply.content_attributes['selected_option']['id']).to eq('manha')
    end

    it 'falls back to the latest native list with the exact id when the rowId has no reference (lists sent before it)' do
      flag_on!
      morning = native_list(%w[manha tarde])
      native_list(%w[centro norte])
      latest = native_list(%w[manha noite])

      expect(receive_reply('tarde').content_attributes['in_reply_to']).to eq(morning.id)
      expect(receive_reply('manha').content_attributes['in_reply_to']).to eq(latest.id)
    end

    it 'keeps the in_reply_to the official path wrote from context, without looking for a list' do
      flag_on!
      native_list(%w[manha])
      official = create(:message, message_type: :outgoing, conversation: conversation, inbox: inbox, account: account,
                                  content: 'Escolha', source_id: 'wamid.lista-oficial')

      reply = receive_reply('manha', context: { from: channel.phone_number, id: 'wamid.lista-oficial' })

      expect(reply.content_attributes['in_reply_to']).to eq(official.id)
    end

    it 'does not search when the answer points to a message (context) the Chatwoot did not find' do
      flag_on!
      native_list(%w[manha])

      reply = receive_reply('manha', context: { from: channel.phone_number, id: 'wamid.desconhecida' })

      # O Chatwoot (Messages::InReplyToMessageBuilder) não achou a mensagem e grava as duas chaves vazias; sem a trava, a
      # busca ligaria a resposta à lista nativa.
      expect(reply.content_attributes['in_reply_to']).to be_nil
    end

    it 'never matches by title, nor a list that went out as text, nor searches without the flag' do
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
