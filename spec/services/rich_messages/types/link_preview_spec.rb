require 'rails_helper'

# chat#1473 (P6): `content_attributes.rich_message` do tipo `link_preview`, texto com a prévia do primeiro link.
describe RichMessages::Types::LinkPreview do
  let(:link) { 'https://exemplo.com.br/proposta?id=42&origem=painel' }
  let(:rich_message) { { type: 'link_preview' } }
  let(:body) { "Sua proposta está pronta: #{link}" }
  let(:graph_recent) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:graph_legacy) { 'https://graph.facebook.com/v13.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.previa' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

  def outgoing(conversation, attrs = {})
    create(:message, { message_type: :outgoing, content: body, conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  def open_window(conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: conversation.inbox,
                     account: conversation.account)
  end

  it 'is the class of the link_preview type and has a text version' do
    expect(RichMessages.type_class('link_preview')).to eq(described_class)
    expect(RichMessages.text_version?(described_class)).to be(true)
  end

  it 'has a blank text version: the text is only the body, which already carries the link' do
    expect(described_class.new('type' => 'link_preview').fallback_text(body)).to eq('')
  end

  describe 'finding a web address in the body' do
    [
      'https://exemplo.com.br',
      'Veja http://exemplo.com.br/a e responda',
      "Primeira linha\nhttps://exemplo.com.br/p",
      'Proposta (https://exemplo.com.br/p).',
      'Veja https://exemplo.com.br.',
      'Sem link aqui, mas este tem: https://exemplo.com.br, ok?',
      'https://açaí.com.br/promoção',
      'Veja HTTPS://EXEMPLO.COM.BR, como no botão de link',
      'Painel em http://192.168.0.10:8080/status'
    ].each do |text|
      it "accepts #{text.inspect}" do
        expect(described_class.new({}).error_for(text)).to be_nil
      end
    end

    {
      'a body without any address' => 'Sua proposta está pronta.',
      'an address without http or https' => 'Acesse www.exemplo.com.br/proposta',
      'an address with another scheme' => 'Baixe em ftp://exemplo.com.br/arquivo',
      'a blank body' => '   '
    }.each do |title, text|
      it "refuses #{title} as having no address" do
        expect(described_class.new({}).error_for(text)).to eq(described_class::NO_WEB_ADDRESS)
      end
    end

    {
      'a scheme without a host' => 'Veja https:// agora',
      'a host that is only punctuation' => 'Veja https://.',
      'a host with an empty part' => 'Veja https://exemplo..com.br',
      'a one-part host the phone cannot reach' => 'Veja http://localhost:3000',
      'a path without a host' => 'Veja https:///caminho',
      'an address the parser rejects (port that is not a number)' => 'Veja https://exemplo.com.br:abc/p',
      'an invalid first address followed by a valid one' => 'Veja https://. ou https://exemplo.com.br'
    }.each do |title, text|
      it "refuses #{title}, because the first address is the one previewed" do
        expect(described_class.new({}).error_for(text)).to eq(described_class::INVALID_FIRST_ADDRESS)
      end
    end

    it 'goes through the parser error for a port that is not a number' do
      expect { Addressable::URI.parse('https://exemplo.com.br:abc/p') }.to raise_error(Addressable::URI::InvalidURIError)
    end

    it 'refuses a body above 4096 characters and accepts the limit itself' do
      at_the_limit = "https://exemplo.com.br/#{'a' * 4073}"

      expect(described_class.new({}).error_for(at_the_limit)).to be_nil
      expect(described_class.new({}).error_for("#{at_the_limit}a")).to eq(described_class::BODY_TOO_LONG)
    end
  end

  context 'with a WhatsApp Cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }

    def envelope(text, context: nil)
      { messaging_product: 'whatsapp', recipient_type: 'individual', context: context, to: '5511937016094', type: 'text',
        text: { body: text, preview_url: true } }.compact
    end

    def deliver(message)
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      message.reload
    end

    def expect_nothing_sent_to_meta
      expect(a_request(:post, graph_recent)).not_to have_been_made
      expect(a_request(:post, graph_legacy)).not_to have_been_made
    end

    context 'when the 24h window is open' do
      before { open_window(conversation) }

      it 'sends one text message with preview_url, with the exact payload' do
        request = stub_request(:post, graph_recent).with(body: envelope(body).to_json).to_return(meta_ok)

        message = deliver(outgoing(conversation))

        expect(request).to have_been_requested.once
        expect(message.source_id).to eq('wamid.previa')
        expect(message.status).to eq('sent')
        expect(RichMessages.delivery_mode(inbox: inbox, type: 'link_preview', conversation: conversation)).to eq(:native)
      end

      it 'quotes the message it replies to' do
        quoted = create(:message, message_type: :incoming, content: 'manda o link', conversation: conversation, inbox: inbox,
                                  account: inbox.account, source_id: 'wamid.anterior')
        request = stub_request(:post, graph_recent)
                  .with(body: envelope(body, context: { message_id: 'wamid.anterior' }).to_json).to_return(meta_ok)

        deliver(outgoing(conversation, content_attributes: { rich_message: rich_message, in_reply_to: quoted.id }))

        expect(request).to have_been_requested.once
      end

      it 'checks the body as it is sent: a markdown link becomes the bare address' do
        request = stub_request(:post, graph_recent).with(body: envelope("Veja #{link}").to_json).to_return(meta_ok)

        message = deliver(outgoing(conversation, content: "Veja [a proposta](#{link})"))

        expect(request).to have_been_requested.once
        expect(message.status).to eq('sent')
      end

      it 'keeps the plain text request untouched without rich_message (v13.0, no preview_url)' do
        request = stub_request(:post, graph_legacy)
                  .with(body: { messaging_product: 'whatsapp', context: nil, to: '5511937016094', text: { body: body }, type: 'text' }.to_json)
                  .to_return(meta_ok)

        message = deliver(outgoing(conversation, content_attributes: {}))

        expect(request).to have_been_requested.once
        expect(message.source_id).to eq('wamid.previa')
      end

      {
        'a body without an address' => [{ content: 'Sua proposta está pronta.' }, described_class::NO_WEB_ADDRESS],
        'a blank body' => [{ content: '' }, described_class::NO_WEB_ADDRESS],
        'an invalid first address' => [{ content: 'Veja https://. ou https://exemplo.com.br' }, described_class::INVALID_FIRST_ADDRESS],
        'a body above 4096 characters' => [{ content: "https://exemplo.com.br #{'a' * 4096}" }, described_class::BODY_TOO_LONG]
      }.each do |title, (message_changes, error)|
        it "fails the message without sending anything for #{title}" do
          message = deliver(outgoing(conversation, message_changes))

          expect(message.status).to eq('failed')
          expect(message.external_error).to eq(error)
          expect_nothing_sent_to_meta
        end
      end
    end

    context 'when the 24h window is closed' do
      it 'fails with the named window error, like plain text, without sending' do
        message = deliver(outgoing(conversation))

        expect(message.status).to eq('failed')
        expect(message.external_error).to eq(I18n.t('errors.whatsapp.message_outside_messaging_window'))
        expect_nothing_sent_to_meta
      end
    end
  end

  context 'with a WhatsApp inbox from another provider (360dialog)' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '123456789') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }

    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      open_window(conversation)
    end

    it 'sends only the body, as plain text' do
      request = stub_request(:post, 'https://waba.360dialog.io/v1/messages')
                .with(body: { 'to' => '123456789', 'text' => { 'body' => body }, 'type' => 'text' }.to_json)
                .to_return(status: 200, body: { 'messages' => [{ 'id' => 'd360' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      message = outgoing(conversation)
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_requested.once
      expect(message.reload.status).to eq('sent')
    end
  end

  it 'gives Telegram the body alone, with nothing appended' do
    channel = create(:channel_telegram)
    message = outgoing(create(:conversation, inbox: channel.inbox, account: channel.account))

    expect(message.outgoing_content).to eq(body)
    expect(RichMessages.delivery_mode(inbox: channel.inbox, type: 'link_preview')).to eq(:text)
  end

  it 'accepts a markdown link on Telegram, whose outgoing text is HTML, as it does on WhatsApp' do
    channel = create(:channel_telegram)
    message = outgoing(create(:conversation, inbox: channel.inbox, account: channel.account), content: "Veja [a proposta](#{link})")

    expect(RichMessages.format_error(message)).to be_nil
  end

  {
    'e-mail' => [:channel_email, 'Channel::Email'],
    'the website chat' => [:channel_widget, 'Channel::WebWidget']
  }.each do |name, (factory, channel_type)|
    it "is refused on #{name}, like every rich_message there" do
      channel = create(factory)
      message = outgoing(create(:conversation, inbox: channel.inbox, account: channel.account))

      expect(RichMessages.format_error(message)).to eq(RichMessages::UNSUPPORTED_CHANNELS.fetch(channel_type))
      expect(RichMessages.delivery_mode(inbox: channel.inbox, type: 'link_preview')).to eq(:refused)
    end
  end
end
