require 'rails_helper'

# chat#1473 (P1a): `content_attributes.rich_message` do tipo `link_button`.
describe RichMessages::Types::LinkButton do
  let(:link) { 'https://exemplo.com.br/proposta?id=42&origem=painel' }
  let(:rich_message) { { type: 'link_button', label: 'Abrir proposta', url: link } }
  let(:body) { 'Sua proposta está pronta.' }
  let(:text_version) { "#{body}\n\nAbrir proposta: #{link}" }
  let(:cta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.botao' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

  def outgoing(conversation, attrs = {})
    create(:message, { message_type: :outgoing, content: body, conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  def open_window(conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: conversation.inbox,
                     account: conversation.account)
  end

  describe 'web addresses with accents' do
    {
      'https://exemplo.com.br/promoção' => 'https://exemplo.com.br/promo%C3%A7%C3%A3o',
      'https://loja.com.br/coleção?cor=açaí' => 'https://loja.com.br/cole%C3%A7%C3%A3o?cor=a%C3%A7a%C3%AD',
      'https://açaí.com.br' => 'https://xn--aa-4iaz.com.br/'
    }.each do |typed, sent_to_meta|
      it "accepts #{typed}, sends it to Meta in ASCII and keeps it readable in the text version" do
        button = described_class.new('label' => 'Abrir', 'url' => typed)

        expect(button.error_for(body)).to be_nil
        expect(button.whatsapp_cloud_payload(body).dig(:interactive, :action, :parameters, :url)).to eq(sent_to_meta)
        expect(button.fallback_text(body)).to eq("Abrir: #{typed}")
      end
    end
  end

  it 'is the class of the link_button type' do
    expect(RichMessages.type_class('link_button')).to eq(described_class)
  end

  context 'with a WhatsApp Cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
    let(:action) { { name: 'cta_url', parameters: { display_text: 'Abrir proposta', url: link } } }

    def envelope(interactive)
      { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094', type: 'interactive', interactive: interactive }
    end

    def deliver(message)
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      message.reload
    end

    context 'when the 24h window is open' do
      before { open_window(conversation) }

      it 'sends one interactive cta_url message with the exact payload' do
        request = stub_request(:post, cta_url)
                  .with(body: envelope({ type: 'cta_url', body: { text: body }, action: action }).to_json).to_return(meta_ok)

        message = deliver(outgoing(conversation))

        expect(request).to have_been_requested.once
        expect(message.source_id).to eq('wamid.botao')
        expect(message.status).not_to eq('failed')
      end

      it 'sends the text header and the footer when they come' do
        interactive = { type: 'cta_url', header: { type: 'text', text: 'Proposta 42' }, body: { text: body },
                        footer: { text: 'Válida por 7 dias' }, action: action }
        request = stub_request(:post, cta_url).with(body: envelope(interactive).to_json).to_return(meta_ok)

        framed = rich_message.merge(header: 'Proposta 42', footer: 'Válida por 7 dias')
        deliver(outgoing(conversation, content_attributes: { rich_message: framed }))

        expect(request).to have_been_requested.once
      end

      it 'puts the link only in the button, never in the body text' do
        sent = nil
        stub_request(:post, cta_url).with { |req| sent = req.body }.to_return(meta_ok)

        deliver(outgoing(conversation))

        interactive = JSON.parse(sent)['interactive']
        expect(interactive.dig('action', 'parameters', 'url')).to eq(link)
        expect(interactive.dig('body', 'text')).to eq(body)
        expect(interactive.to_s.scan(link).size).to eq(1)
      end

      it 'keeps the plain text request untouched without rich_message' do
        request = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
                  .with(body: { messaging_product: 'whatsapp', context: nil, to: '5511937016094', text: { body: body }, type: 'text' }.to_json)
                  .to_return(meta_ok)

        message = deliver(outgoing(conversation, content_attributes: {}))

        expect(request).to have_been_requested.once
        expect(message.source_id).to eq('wamid.botao')
      end

      {
        'a blank label' => [{ label: ' ' }, {}, described_class::LABEL_BLANK],
        'a missing label' => [{ label: nil }, {}, described_class::LABEL_BLANK],
        'a label above 20 characters' => [{ label: 'a' * 21 }, {}, described_class::LABEL_TOO_LONG],
        'a link without http or https' => [{ url: 'exemplo.com.br/proposta' }, {}, described_class::INVALID_URL],
        'a link with another scheme' => [{ url: 'ftp://exemplo.com.br/x' }, {}, described_class::INVALID_URL],
        'a link without a host' => [{ url: 'https://' }, {}, described_class::INVALID_URL],
        'a link with only a path' => [{ url: 'https:///caminho' }, {}, described_class::INVALID_URL],
        'a link with a space' => [{ url: 'https://exemplo.com.br/a b' }, {}, described_class::INVALID_URL],
        'a link with a quote' => [{ url: "https://exemplo.com.br/a'b" }, {}, described_class::INVALID_URL],
        'a link with a double quote' => [{ url: 'https://exemplo.com.br/a"b' }, {}, described_class::INVALID_URL],
        'a link with angle brackets' => [{ url: 'https://exemplo.com.br/<script>' }, {}, described_class::INVALID_URL],
        'a link that is not text' => [{ url: 42 }, {}, described_class::INVALID_URL],
        'a link above 2000 characters' => [{ url: "https://exemplo.com.br/#{'a' * 1978}" }, {}, described_class::URL_TOO_LONG],
        'a missing link' => [{ url: nil }, {}, described_class::INVALID_URL],
        'a blank body' => [{}, { content: '' }, described_class::BODY_BLANK],
        'a body above 1024 characters' => [{}, { content: 'a' * 1025 }, described_class::BODY_TOO_LONG],
        'a header above 60 characters' => [{ header: 'a' * 61 }, {}, described_class::HEADER_INVALID],
        'a blank header' => [{ header: ' ' }, {}, described_class::HEADER_INVALID],
        'a footer above 60 characters' => [{ footer: 'a' * 61 }, {}, described_class::FOOTER_INVALID],
        'a footer that is not text' => [{ footer: 7 }, {}, described_class::FOOTER_INVALID]
      }.each do |title, (rich_changes, message_changes, error)|
        it "fails the message without sending anything for #{title}" do
          message = outgoing(conversation, { content_attributes: { rich_message: rich_message.merge(rich_changes) } }.merge(message_changes))

          deliver(message)

          expect(message.status).to eq('failed')
          expect(message.external_error).to eq(error)
          expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
        end
      end

      it 'accepts the limits themselves (20 character label, 1024 character body, 60 character header and footer)' do
        stub_request(:post, cta_url).to_return(meta_ok)
        at_the_limit = rich_message.merge(label: 'a' * 20, header: 'a' * 60, footer: 'a' * 60)
        message = outgoing(conversation, content: 'a' * 1024, content_attributes: { rich_message: at_the_limit })

        expect(deliver(message).status).not_to eq('failed')
      end

      it 'measures the body that is actually sent, not the text as typed' do
        stub_request(:post, cta_url).with(body: hash_including('interactive' => hash_including('body' => { 'text' => "*#{'a' * 1022}*" })))
                                    .to_return(meta_ok)

        expect(deliver(outgoing(conversation, content: "**#{'a' * 1022}**")).status).not_to eq('failed')
      end
    end

    context 'when the 24h window is closed' do
      it 'fails with the named window error, without a template and without sending' do
        message = deliver(outgoing(conversation))

        expect(message.status).to eq('failed')
        expect(message.external_error).to eq(I18n.t('errors.whatsapp.message_outside_messaging_window'))
        expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
      end

      context 'with WhatsApp Híbrido ready' do
        let(:client) { instance_double(Waha::Client) }

        around { |example| with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: inbox.account_id.to_s) { example.run } }

        before do
          WhatsappHybrid::Connection.create!(
            account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
            connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
          )
          allow(Waha::Client).to receive(:new).and_return(client)
          allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                            new_message_id: '3EB0AAAA', start_typing: {}, stop_typing: {}, send_text: { 'id' => 'x' })
          allow(Kernel).to receive(:sleep)
          Redis::Alfred.delete('whatsapp_hybrid:chat_id:hybrid-test:5511937016094')
        end

        it 'sends body, label and link as text through the real WebTransport' do
          message = deliver(outgoing(conversation, sender: create(:user, account: inbox.account)))

          expect(client).to have_received(:send_text).with(session: 'hybrid-test', chat_id: '5511937016094@c.us',
                                                           text: text_version, id: '3EB0AAAA')
          expect(message.status).not_to eq('failed')
          expect(message.content_attributes['rich_message']).to include('type' => 'link_button', 'url' => link)
        end
      end
    end

    it 'leaves the campaign free text object (not a Message) on the plain text request' do
      request = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
                .with(body: { messaging_product: 'whatsapp', context: nil, to: '5511937016094', text: { body: 'Olá, Ana' }, type: 'text' }.to_json)
                .to_return(meta_ok)

      source_id = channel.provider_service.send_message('5511937016094', CampaignJourney::ConversaAberta::TextoDeEnvio.new('Olá, Ana'))

      expect(request).to have_been_requested.once
      expect(source_id).to eq('wamid.botao')
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

    it 'sends body, label and link as text' do
      request = stub_request(:post, 'https://waba.360dialog.io/v1/messages')
                .with(body: { 'to' => '123456789', 'text' => { 'body' => text_version }, 'type' => 'text' }.to_json)
                .to_return(status: 200, body: { 'messages' => [{ 'id' => 'd360' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      message = outgoing(conversation)
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_requested.once
      expect(message.reload.status).not_to eq('failed')
    end
  end

  context 'with channels whose outgoing text is HTML' do
    let(:rich_message) { { type: 'link_button', label: 'Ver <oferta>', url: link, header: 'Topo', footer: 'Fim' } }
    let(:escaped) { 'Ver &lt;oferta&gt;: https://exemplo.com.br/proposta?id=42&amp;origem=painel' }

    def message_on(channel_factory)
      channel = create(channel_factory)
      outgoing(create(:conversation, inbox: channel.inbox, account: channel.account))
    end

    it 'escapes label and link on Telegram, without header or footer' do
      expect(message_on(:channel_telegram).outgoing_content).to eq("#{body}\n\n#{escaped}")
    end

    {
      'label' => 'LABEL_MULTILINE', 'header' => 'HEADER_INVALID', 'footer' => 'FOOTER_INVALID'
    }.each do |field, error|
      it "refuses a #{field} with a line break" do
        button = described_class.new(rich_message.stringify_keys.merge(field => "uma\nduas"))

        expect(button.error_for(body)).to eq(described_class.const_get(error))
        expect(described_class.new(rich_message.stringify_keys.merge(field => "uma\rduas")).error_for(body)).to be_present
      end
    end

    it 'fails an invalid rich message on Telegram instead of sending it as text' do
      stub_request(:post, /api\.telegram\.org/)
      channel = create(:channel_telegram)
      message = outgoing(create(:conversation, inbox: channel.inbox, account: channel.account),
                         content_attributes: { rich_message: rich_message.merge(url: 'ftp://exemplo.com.br') })

      Telegram::SendOnTelegramService.new(message: message).perform

      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq(described_class::INVALID_URL)
      expect(a_request(:post, /api\.telegram\.org/)).not_to have_been_made
    end
  end
end
