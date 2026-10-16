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
    before { flag_on! }

    # A marca da criação depende do motor: aqui a lista já saiu nativa.
    def native_list(ids, on: conversation, source_id: '3EB0LISTA')
      list = create(:message, message_type: :outgoing, content: 'Qual?', conversation: on, inbox: on.inbox, account: account,
                              source_id: source_id,
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
      expect(attributes).to include('in_reply_to' => list.id, 'in_reply_to_external_id' => '3EB0LISTA')
      expect(attributes).not_to have_key('waha_list_reply')
    end

    it 'without a reference, links to the latest native list of the conversation that offered that exact option' do
      older = native_list(%w[manha tarde])
      native_list(%w[noite])

      attributes = reply('tarde').content_attributes

      expect(attributes['selected_option']).to eq('id' => 'tarde', 'title' => 'Manhã')
      expect(attributes['in_reply_to']).to eq(older.id)
    end

    # Escolha sem lista nossa que a ofereceu (forja, lista de outra conversa ou caixa, lista que saiu como texto): fica
    # texto comum.
    it 'records no choice when no native list of this conversation and inbox offered the option' do
      other_conversation = native_list(%w[manha], on: create(:conversation, inbox: inbox, account: account))
      other_inbox = native_list(%w[manha], on: create(:conversation, inbox: create(:channel_api, account: account).inbox, account: account))
      text_list = create(:message, message_type: :outgoing, content: 'Qual?', conversation: conversation, inbox: inbox, account: account,
                                   content_attributes: { rich_message: { type: 'options', options: [{ id: 'tarde', title: 'Tarde' }] } })
      text_list.update!(content_attributes: text_list.content_attributes.merge('rich_message_sent_as' => 'text'))

      ["manha|#{other_conversation.id}", "manha|#{other_inbox.id}", 'manha', "tarde|#{text_list.id}", 'tarde'].each do |row_id|
        attributes = reply(row_id).content_attributes
        expect(attributes.keys & %w[selected_option in_reply_to waha_list_reply]).to eq([]), row_id
      end
    end

    it 'does not write the provisional source_id as in_reply_to_external_id' do
      list = native_list(%w[manha], source_id: 'waha-native-pending-1')

      attributes = reply("manha|#{list.id}").content_attributes

      expect(attributes['in_reply_to']).to eq(list.id)
      expect(attributes['in_reply_to_external_id']).to be_blank
    end

    it 'keeps the in_reply_to the connector already filled' do
      list = native_list(%w[manha])
      quoted = create(:message, message_type: :outgoing, content: 'x', conversation: conversation, inbox: inbox, account: account)

      expect(reply("manha|#{list.id}", in_reply_to: quoted.id).content_attributes['in_reply_to']).to eq(quoted.id)
    end

    # O conector patchado manda a chave em toda caixa: sem a flag, ela fica exatamente como veio (igual à main).
    it 'leaves waha_list_reply untouched and records no choice without the flag' do
      list = native_list(%w[manha])
      account.disable_features!(Waha::RichNative::FLAG)

      attributes = reply("manha|#{list.id}").content_attributes

      expect(attributes['waha_list_reply']).to eq('row_id' => "manha|#{list.id}", 'title' => 'Manhã')
      expect(attributes.keys & %w[selected_option in_reply_to]).to eq([])
    end

    it 'drops the key even when the conversion breaks' do
      list = native_list(%w[manha])
      allow(Waha::RichNative).to receive(:split_row_id).and_raise(ActiveRecord::ConnectionFailed)

      expect(reply("manha|#{list.id}").content_attributes).not_to have_key('waha_list_reply')
    end
  end

  # Nada de HTTP ao criar a mensagem: só o cache, que o job do cron preenche. Sem stub no WebMock, uma chamada ao motor
  # quebraria o teste.
  describe 'with the real engine capability cache' do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(Rails).to receive(:cache).and_return(cache)
      allow(Waha::EngineCapabilities).to receive(:types).and_call_original
      flag_on!
    end

    it 'goes as text with nothing cached, and natively once the job cached the engine, never calling the engine' do
      expect(outgoing.reload.content_attributes['rich_message_sent_as']).to eq('text')

      cache.write(Waha::EngineCapabilities.cache_key("#{engine}/"), %w[options], expires_in: 10.minutes)
      expect(outgoing.reload.content_attributes['rich_message_sent_as']).to eq('native')
      expect(a_request(:get, "#{engine}/api/server/version")).not_to have_been_made
    end
  end

  describe 'retry (Waha::RichNative::RetryAsText)', type: :request do
    let(:agent) { create(:user, account: account, role: :agent) }

    def native_failed(on_inbox, on_conversation)
      message = create(:message, message_type: :outgoing, content: 'Qual horário?', conversation: on_conversation, inbox: on_inbox,
                                 account: account, content_attributes: { rich_message: options })
      message.update!(status: :failed, content_attributes: message.content_attributes.merge('rich_message_sent_as' => 'native'))
      message
    end

    def retry_message(message)
      create(:inbox_member, inbox: message.inbox, user: agent)
      post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      message.reload.content_attributes
    end

    it 'turns the native mark into text on a WAHA inbox, since the message_updated delivers only the text' do
      flag_on!

      attributes = retry_message(native_failed(inbox, conversation))

      expect(attributes).to include('rich_message_sent_as' => 'text', 'rich_message_sent_text' => "Qual horário?\n\n1. Manhã\n2. Tarde")
    end

    it 'changes nothing on an API inbox that is not WAHA (the mark stays, as RetryKeepsFormat keeps it there)' do
      api = create(:channel_api, account: account, webhook_url: 'https://bridge.example.com/hook')
      message = native_failed(api.inbox, create(:conversation, inbox: api.inbox, account: account))
      marks = message.content_attributes.slice('rich_message_sent_as', 'rich_message_sent_text')

      attributes = retry_message(message)

      expect(attributes['rich_message_sent_as']).to eq('native')
      expect(attributes.slice('rich_message_sent_as', 'rich_message_sent_text')).to eq(marks)
    end

    it 'changes nothing on a hybrid inbox (RetryKeepsFormat drops the mark, the next send decides again)' do
      hybrid = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false, account: account)

      attributes = retry_message(native_failed(hybrid.inbox, create(:conversation, inbox: hybrid.inbox, account: account)))

      expect(attributes.keys & %w[rich_message_sent_as rich_message_sent_text]).to eq([])
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
