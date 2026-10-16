require 'rails_helper'

# chat#1709 (fase 2): caixa WAHA comum. Quem envia é o conector do WAHA; o chat2you decide na criação, entrega o pedido
# (`waha_native`) no webhook da caixa e lê a volta (`waha_list_reply`).
describe Waha::RichNative::WahaInbox do
  let(:engine) { 'https://waha.example' }
  let(:channel) do
    create(:channel_api, webhook_url: "#{engine}/webhooks/chatwoot/abc", additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:options) { { type: 'options', options: [{ id: 'manha', title: 'Manhã' }, { id: 'tarde', title: 'Tarde' }] } }
  let(:capabilities) { %w[options location contact] }
  let(:listener) { WebhookListener.instance }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/") { example.run } }

  before { allow(Waha::EngineCapabilities).to receive(:types) { |url| url == "#{engine}/" ? capabilities : [] } }

  def flag_on!
    account.enable_features!(Waha::RichNative::FLAG)
  end

  def outgoing(rich_message = options, content: 'Qual horário?')
    create(:message, message_type: :outgoing, content: content, conversation: conversation, inbox: inbox, account: account,
                     content_attributes: { rich_message: rich_message })
  end

  def inbox_payload(message, event: :message_created)
    payloads = []
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| payloads << payload if kind == :api_inbox_webhook }
    listener.public_send(event, Events::Base.new(event, Time.zone.now, message: message))
    payloads.sole
  end

  describe 'the single decision at creation' do
    it 'marks native and delivers the engine request with the message reference, keeping the text as the content' do
      flag_on!
      account.update!(locale: 'pt_BR')
      message = outgoing

      payload = inbox_payload(message)

      expect(message.reload.content_attributes['rich_message_sent_as']).to eq('native')
      expect(payload[:content]).to eq("Qual horário?\n\n1. Manhã\n2. Tarde")
      expect(payload[:content_attributes]['waha_native']).to eq(
        'kind' => 'sendList',
        'payload' => { 'message' => { 'title' => 'Qual horário?', 'button' => 'Ver opções',
                                      'sections' => [{ 'title' => 'Ver opções',
                                                       'rows' => [{ 'title' => 'Manhã', 'rowId' => "manha|#{message.id}" },
                                                                  { 'title' => 'Tarde', 'rowId' => "tarde|#{message.id}" }] }] } }
      )
    end

    it 'keeps the mark and the request equal when the engine capability changes between creation and delivery' do
      flag_on!
      native = outgoing
      allow(Waha::EngineCapabilities).to receive(:types).and_return([])
      text = outgoing

      expect(inbox_payload(native)[:content_attributes]).to have_key('waha_native')
      allow(Waha::EngineCapabilities).to receive(:types).and_return(capabilities)
      expect(inbox_payload(text)[:content_attributes]).not_to have_key('waha_native')
      expect([native, text].map { |message| message.reload.content_attributes['rich_message_sent_as'] }).to eq(%w[native text])
    end

    it 'sends location and contact as their endpoints' do
      flag_on!
      location = outgoing({ type: 'location', latitude: -23.5, longitude: -46.6, name: 'Unidade' }, content: '')
      contact = outgoing({ type: 'contact', name: 'Recepção', phone: '+55 11 4000-0473' }, content: '')

      expect(inbox_payload(location)[:content_attributes]['waha_native'])
        .to eq('kind' => 'sendLocation', 'payload' => { 'latitude' => -23.5, 'longitude' => -46.6, 'title' => 'Unidade' })
      expect(inbox_payload(contact)[:content_attributes]['waha_native'])
        .to eq('kind' => 'sendContactVcard', 'payload' => { 'contacts' => [{ 'fullName' => 'Recepção', 'phoneNumber' => '+55 11 4000-0473' }] })
    end

    it 'stays text with an engine outside the list' do
      flag_on!
      channel.update!(webhook_url: 'https://outro-motor.example/webhooks/chatwoot/abc')
      message = outgoing

      expect(inbox_payload(message)[:content_attributes]).not_to have_key('waha_native')
      expect(message.reload.content_attributes['rich_message_sent_as']).to eq('text')
    end

    it 'stays text without the flag, with an empty engine list, or for a type the engine does not declare' do
      contact = { type: 'contact', name: 'Recepção', phone: '+55 11 4000-0473' }
      without_flag = outgoing
      flag_on!
      empty_list = with_modified_env(WAHA_RICH_NATIVE_ENGINES: '') { outgoing }
      allow(Waha::EngineCapabilities).to receive(:types).and_return(%w[options])
      undeclared = outgoing(contact, content: '')

      marks = [without_flag, empty_list, undeclared].map { |message| message.reload.content_attributes['rich_message_sent_as'] }
      expect(marks).to eq(%w[text text text])
    end

    # Motor sem o conector customizado: ignora `waha_native` e manda o `content`, que é o texto completo.
    it 'delivers the full text as the content to an engine without the patch' do
      flag_on!
      allow(Waha::EngineCapabilities).to receive(:types).and_return([])
      message = outgoing

      payload = inbox_payload(message)

      expect(payload[:content]).to eq("Qual horário?\n\n1. Manhã\n2. Tarde")
      expect(payload[:content_attributes]).not_to have_key('waha_native')
    end

    it 'does not send the request again on message_updated' do
      flag_on!

      expect(inbox_payload(outgoing, event: :message_updated)[:content_attributes]).not_to have_key('waha_native')
    end
  end

  describe 'the customer choice (waha_list_reply)' do
    # A marca da criação depende do motor: aqui a lista já saiu nativa.
    def native_list(ids, on: conversation)
      list = create(:message, message_type: :outgoing, content: 'Qual?', conversation: on, inbox: on.inbox, account: account,
                              content_attributes: { rich_message: { type: 'options', options: ids.map { |id| { id: id, title: id } } } })
      list.update!(content_attributes: list.content_attributes.merge('rich_message_sent_as' => 'native'))
      list
    end

    def reply(row_id, extra = {})
      create(:message, message_type: :incoming, content: 'Manhã', conversation: conversation, inbox: inbox, account: account,
                       content_attributes: { waha_list_reply: { row_id: row_id, title: 'Manhã' } }.merge(extra)).reload
    end

    it 'turns the reference into in_reply_to and the original option id, and drops the contract key' do
      list = native_list(%w[manha tarde])

      attributes = reply("manha|#{list.id}").content_attributes

      expect(attributes['selected_option']).to eq('id' => 'manha', 'title' => 'Manhã')
      expect(attributes['in_reply_to']).to eq(list.id)
      expect(attributes).not_to have_key('waha_list_reply')
    end

    it 'keeps the id whole and links nothing without a reference' do
      native_list(%w[manha])

      attributes = reply('manha').content_attributes

      expect(attributes['selected_option']).to eq('id' => 'manha', 'title' => 'Manhã')
      expect(attributes['in_reply_to']).to be_blank
    end

    it 'never links to a list of another conversation or inbox, but still drops the reference from the option id' do
      other_conversation = native_list(%w[manha], on: create(:conversation, inbox: inbox, account: account))
      other_inbox = native_list(%w[manha], on: create(:conversation, inbox: create(:channel_api, account: account).inbox, account: account))

      [other_conversation, other_inbox].each do |list|
        attributes = reply("manha|#{list.id}").content_attributes
        expect(attributes['in_reply_to']).to be_blank
        expect(attributes['selected_option']['id']).to eq('manha')
      end
    end

    it 'keeps the in_reply_to the connector already filled' do
      list = native_list(%w[manha])
      quoted = create(:message, message_type: :outgoing, content: 'x', conversation: conversation, inbox: inbox, account: account)

      expect(reply("manha|#{list.id}", in_reply_to: quoted.id).content_attributes['in_reply_to']).to eq(quoted.id)
    end
  end

  describe 'Waha::RichNative.types_for and RichMessages.delivery_mode' do
    it 'answers the engine types for a WAHA conversation with the flag, and nothing without it' do
      expect(Waha::RichNative.types_for(conversation)).to eq([])

      flag_on!
      allow(Waha::EngineCapabilities).to receive(:types).and_return(%w[options location])
      expect(Waha::RichNative.types_for(conversation.reload)).to eq(%w[options location])
    end

    it 'is native in delivery_mode only for a message with the same rule as the creation' do
      flag_on!
      draft = Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content_type: :text,
                          content: 'Qual horário?', content_attributes: { rich_message: options })

      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation, message: draft)).to eq(:native)
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:text)
    end

    [true, false].each do |flag|
      it "adds no query for WAHA conversations in the list with the flag #{flag ? 'on' : 'off'}" do
        flag_on! if flag
        ids = Array.new(3) { create(:conversation, inbox: inbox, account: account).id }
        loaded = Conversation.where(id: ids).preload(inbox: :channel).to_a
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }
        Current.account = Account.find(account.id)

        result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          loaded.map { |item| Waha::RichNative.types_for(item, api_reply: false) }
        end

        expect(result).to all(eq(flag ? capabilities : []))
        expect(queries).to be_empty
      ensure
        Current.reset
      end
    end
  end
end
