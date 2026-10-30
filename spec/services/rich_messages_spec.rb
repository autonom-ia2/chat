require 'rails_helper'

# chat#1473: o encaixe dos envios ricos, provado com tipos que só existem neste spec. Nada aqui (nem em `app/`)
# conhece um tipo específico: acrescentar um tipo é criar a classe dele em RichMessages::Types.
describe RichMessages do
  let(:spec_type) do
    Class.new do
      def initialize(payload)
        @code = payload['code']
      end

      def error_for(_body)
        'Carimbo sem código.' if @code.blank?
      end

      def whatsapp_cloud_payload(body)
        raise RichMessages::DeliveryError, 'Carimbo indisponível agora.' if @code == 'boom'

        { type: 'spec_stamp', spec_stamp: { code: @code, text: body } }
      end

      def fallback_text(_body)
        return '' if @code == 'bare'

        "Carimbo <#{@code}> & cia"
      end
    end
  end
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, account: inbox.account) }
  let(:meta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.rico' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }
  let(:window_open) { true }

  before do
    stub_const('RichMessages::Types::SpecStamp', spec_type)
    stub_const('RichMessages::Types::SpecMute', Class.new(spec_type) { def self.text_version? = false })
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: inbox.account) if window_open
  end

  def outgoing(rich_message, attrs = {}, in_conversation = conversation)
    create(:message, { message_type: :outgoing, content: 'Corpo', conversation: in_conversation, inbox: in_conversation.inbox,
                       account: in_conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  def deliver(message)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  def expect_failed(message, error)
    expect(message.status).to eq('failed')
    expect(message.external_error).to eq(error)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  describe 'on WhatsApp Cloud' do
    it 'sends whatever the type builds, in a single message' do
      request = stub_request(:post, meta_url)
                .with(body: { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094',
                              type: 'spec_stamp', spec_stamp: { code: 'A1', text: 'Corpo' } }.to_json)
                .to_return(meta_ok)

      message = deliver(outgoing({ type: 'spec_stamp', code: 'A1' }))

      expect(request).to have_been_requested.once
      expect(message.source_id).to eq('wamid.rico')
    end

    it 'quotes the message it replies to' do
      request = stub_request(:post, meta_url).with(body: hash_including('context' => { 'message_id' => 'wamid.citada' })).to_return(meta_ok)

      quoted = create(:message, message_type: :incoming, content: 'e o valor?', conversation: conversation, inbox: inbox,
                                account: inbox.account, source_id: 'wamid.citada')

      deliver(outgoing({ type: 'spec_stamp', code: 'A1' },
                       content_attributes: { rich_message: { type: 'spec_stamp', code: 'A1' }, in_reply_to: quoted.id }))

      expect(request).to have_been_requested.once
    end

    it 'fails the message with the error of the type, without sending' do
      expect_failed(deliver(outgoing({ type: 'spec_stamp' })), 'Carimbo sem código.')
    end

    it 'fails the message when the type raises a DeliveryError while building the payload' do
      expect_failed(deliver(outgoing({ type: 'spec_stamp', code: 'boom' })), 'Carimbo indisponível agora.')
    end

    it 'fails, instead of sending the body as plain text, an unknown type that reaches the provider without the guard' do
      message = outgoing({ type: 'carousel' })

      expect(channel.provider_service.send_message('5511937016094', message)).to be_nil

      expect_failed(message.reload, described_class::UNKNOWN_TYPE)
    end

    it 'marks the message as failed with the error returned by Meta' do
      stub_request(:post, meta_url).to_return(status: 400, body: { error: { message: '(#100) Invalid parameter' } }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

      message = deliver(outgoing({ type: 'spec_stamp', code: 'A1' }))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq('(#100) Invalid parameter')
    end

    it 'sends a type without a text version' do
      stub_request(:post, meta_url).to_return(meta_ok)

      expect(deliver(outgoing({ type: 'spec_mute', code: 'A1' })).status).not_to eq('failed')
    end

    context 'when the 24h window is closed' do
      let(:window_open) { false }

      it 'fails a type without a text version with the window error (no text transport can carry it)' do
        expect_failed(deliver(outgoing({ type: 'spec_mute', code: 'A1' })), I18n.t('errors.whatsapp.message_outside_messaging_window'))
      end
    end
  end

  # Sem a chave `rich_message`, cada prepend cai no caminho original na primeira linha: nada do módulo roda além
  # da checagem da chave.
  describe 'a message without rich_message' do
    let(:plain) do
      create(:message, message_type: :outgoing, content: 'Corpo', conversation: conversation, inbox: inbox, account: inbox.account)
    end

    before do
      plain
      [:html_channel?, :text_with_fallback, :error_for, :format_error, :build, :body_text, :whatsapp_cloud?].each do |entry|
        allow(described_class).to receive(entry).and_call_original
      end
    end

    def expect_only_the_key_check
      [:html_channel?, :text_with_fallback, :error_for, :format_error, :build, :body_text, :whatsapp_cloud?].each do |entry|
        expect(described_class).not_to have_received(entry)
      end
    end

    it 'has the original outgoing text without reading the inbox or the renderer map' do
      expect(Message.find(plain.id).outgoing_content).to eq('Corpo')

      expect_only_the_key_check
    end

    it 'goes through the send service and the WhatsApp Cloud text request untouched' do
      request = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
                .with(body: { messaging_product: 'whatsapp', context: nil, to: '5511937016094', text: { body: 'Corpo' }, type: 'text' }.to_json)
                .to_return(meta_ok)
      allow(described_class).to receive(:html_channel?).and_call_original

      deliver(plain)

      expect(request).to have_been_requested.once
      expect_only_the_key_check
    end
  end

  describe 'what does not go to the channel' do
    it 'leaves a private note with an invalid rich_message alone' do
      message = deliver(outgoing({ type: 'carousel' }, private: true))

      expect(message.status).not_to eq('failed')
      expect(message.external_error).to be_nil
    end

    it 'leaves a message that came from the channel alone' do
      message = deliver(outgoing({ type: 'carousel' }, source_id: 'wamid.eco'))

      expect(message.status).not_to eq('failed')
    end
  end

  describe 'combinations that cannot go out' do
    it 'fails rich_message together with a template' do
      message = outgoing({ type: 'spec_stamp', code: 'A1' }, additional_attributes: { template_params: { name: 'x', language: 'pt_BR' } })

      expect_failed(deliver(message), described_class::WITH_TEMPLATE)
    end

    it 'fails rich_message on a message that is not plain text' do
      with_items = { rich_message: { type: 'spec_stamp', code: 'A1' }, items: [{ title: 'Sim', value: 'sim' }] }
      message = outgoing({ type: 'spec_stamp', code: 'A1' }, content_type: 'input_select', content_attributes: with_items)

      expect_failed(deliver(message), described_class::NOT_PLAIN_TEXT)
    end

    it 'fails rich_message together with an attachment' do
      message = outgoing({ type: 'spec_stamp', code: 'A1' })
      attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
      attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      attachment.save!

      expect_failed(deliver(message), described_class::WITH_ATTACHMENT)
    end
  end

  describe 'the outgoing text of the other channels' do
    def message_on(channel_factory, rich_message, attrs = {})
      other = create(channel_factory)
      outgoing(rich_message, attrs, create(:conversation, inbox: other.inbox, account: other.account))
    end

    it 'joins body and text version with a blank line on a plain text channel, untouched' do
      expect(message_on(:channel_line, { type: 'spec_stamp', code: 'A1' }).outgoing_content).to eq("Corpo\n\nCarimbo <A1> & cia")
    end

    it 'escapes the text version where the outgoing text is HTML (Telegram)' do
      expect(message_on(:channel_telegram, { type: 'spec_stamp', code: 'A1' }).outgoing_content)
        .to eq("Corpo\n\nCarimbo &lt;A1&gt; &amp; cia")
    end

    it 'is only the body when the text version of the type is blank' do
      message = message_on(:channel_line, { type: 'spec_stamp', code: 'bare' })

      expect(message.outgoing_content).to eq('Corpo')
      expect(described_class.error_for(message)).to be_nil
    end

    it 'refuses e-mail, whose send does not read the outgoing text' do
      message = message_on(:channel_email, { type: 'spec_stamp', code: 'A1' })

      Email::SendOnEmailService.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq(described_class::UNSUPPORTED_CHANNELS.fetch('Channel::Email'))
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'refuses the website widget, which shows the raw content' do
      message = message_on(:channel_widget, { type: 'spec_stamp', code: 'A1' })

      expect(described_class.format_error(message)).to eq(described_class::UNSUPPORTED_CHANNELS.fetch('Channel::WebWidget'))
    end

    it 'is only the text version when the body is empty' do
      expect(message_on(:channel_line, { type: 'spec_stamp', code: 'A1' }, content: nil).outgoing_content).to eq('Carimbo <A1> & cia')
    end

    it 'keeps the plain outgoing text for an unknown type' do
      expect(message_on(:channel_line, { type: 'carousel' }).outgoing_content).to eq('Corpo')
    end

    it 'fails a type without a text version instead of sending only the body' do
      stub_request(:post, /api\.telegram\.org/)
      message = message_on(:channel_telegram, { type: 'spec_mute', code: 'A1' })

      Telegram::SendOnTelegramService.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq(described_class::NO_TEXT_VERSION)
      expect(a_request(:post, /api\.telegram\.org/)).not_to have_been_made
    end
  end

  describe '.text_capable?' do
    it 'is true for a message without rich_message, checking only the key' do
      plain = create(:message, message_type: :outgoing, content: 'Corpo', conversation: conversation, inbox: inbox, account: inbox.account)
      allow(described_class).to receive(:build).and_call_original

      expect(described_class.text_capable?(plain)).to be(true)
      expect(described_class).not_to have_received(:build)
    end

    it 'is true for a type with a text version, even a blank one, and false for a type without one' do
      expect(described_class.text_capable?(outgoing({ type: 'spec_stamp', code: 'A1' }))).to be(true)
      expect(described_class.text_capable?(outgoing({ type: 'spec_stamp', code: 'bare' }))).to be(true)
      expect(described_class.text_capable?(outgoing({ type: 'spec_mute', code: 'A1' }))).to be(false)
    end

    it 'is false for a type that does not exist, so no text transport sends only its body' do
      message = outgoing({ type: 'carousel' })

      expect(described_class.text_capable?(message)).to be(false)
      expect(described_class.text_capable?(outgoing({}))).to be(false)
      expect(described_class.error_for(message)).to eq(described_class::UNKNOWN_TYPE)
    end
  end

  describe 'a conversation above the messages per minute limit' do
    around { |example| with_modified_env(CONVERSATION_MESSAGE_PER_MINUTE_LIMIT: '1') { example.run } }

    def over_the_limit(rich_message)
      message = with_modified_env(CONVERSATION_MESSAGE_PER_MINUTE_LIMIT: '200') { outgoing(rich_message) }
      expect(message).not_to be_valid
      message
    end

    it 'still fails a message that cannot go out, instead of raising and leaving it as sent' do
      expect_failed(deliver(over_the_limit({ type: 'carousel' })), described_class::UNKNOWN_TYPE)
    end

    it 'still fails a message whose type raised a DeliveryError' do
      expect_failed(deliver(over_the_limit({ type: 'spec_stamp', code: 'boom' })), 'Carimbo indisponível agora.')
    end
  end

  describe 'the request log' do
    it 'filters rich_message, which carries the link and, in other types, form data' do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      # `content` também sai do log desde o #2103 (e casa `content_attributes` inteiro); aqui fica só o rich_message.
      filtered = filter.filter('message' => { 'rich_message' => { 'type' => 'spec_stamp', 'code' => 'A1' } })

      expect(filtered).to eq('message' => { 'rich_message' => '[FILTERED]' })
    end
  end

  describe 'an unknown or unsafe type' do
    before do
      stub_const('RichMessages::Types::NotAClass', Module.new)
      stub_const('RichMessages::Types::HalfType', Class.new { def error_for(_body); end })
    end

    {
      'a type nobody defined' => 'carousel',
      'an empty type' => '',
      'a missing type' => nil,
      'a type that is not text' => 42,
      'a type with ::' => 'spec_stamp::x',
      'a type with a leading ::' => '::Message',
      'a type with a slash' => 'types/spec_stamp',
      'a type starting with a number' => '1stamp',
      'a type written as a constant' => 'SpecStamp',
      'a type with a doubled underscore' => 'spec__stamp',
      'a type with a trailing underscore' => 'spec_stamp_',
      'a type that names a top-level class' => 'message',
      'a type that names Object' => 'object',
      'a type that names a class outside RichMessages::Types' => 'send_guard',
      'a type that names a module' => 'not_a_class',
      'a type whose class lacks the interface' => 'half_type'
    }.each do |title, type|
      it "fails the message as an unknown format for #{title}" do
        expect(described_class.type_class(type)).to be_nil
        expect_failed(deliver(outgoing({ type: type, code: 'A1' })), described_class::UNKNOWN_TYPE)
      end
    end

    [{}, '', [], false, 'spec_stamp'].each do |value|
      it "fails a rich_message that is #{value.inspect}" do
        expect_failed(deliver(outgoing(value)), described_class::UNKNOWN_TYPE)
      end
    end
  end
end
