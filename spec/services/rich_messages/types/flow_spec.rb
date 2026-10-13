require 'rails_helper'

# chat#1473 (P2a): `content_attributes.rich_message` do tipo `flow` (formulário do WhatsApp).
describe RichMessages::Types::Flow do
  let(:data) { { 'produto' => 'auto', 'campos' => { 'cep' => '01001000' } } }
  let(:rich_message) do
    { type: 'flow', flow_id: '1234567890', cta: 'Iniciar', token: 'sessao-1739999999-123456', screen: 'LOGIN', data: data }
  end
  let(:body) { 'Para seguir com a proposta, entre com seus dados.' }
  let(:graph_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.flow' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

  def outgoing(conversation, attrs = {})
    create(:message, { message_type: :outgoing, content: body, conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  def open_window(conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: conversation.inbox,
                     account: conversation.account)
  end

  def deliver(message)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  it 'is the class of the flow type and has no text version' do
    expect(RichMessages.type_class('flow')).to eq(described_class)
    expect(described_class.text_version?).to be(false)
  end

  context 'with a WhatsApp Cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
    let(:parameters) do
      { flow_message_version: '3', flow_token: 'sessao-1739999999-123456', flow_id: '1234567890', flow_cta: 'Iniciar',
        flow_action: 'navigate', flow_action_payload: { screen: 'LOGIN', data: data } }
    end

    def envelope(interactive)
      { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094', type: 'interactive', interactive: interactive }
    end

    context 'when the 24h window is open' do
      before { open_window(conversation) }

      it 'sends one interactive flow message with the exact payload' do
        interactive = { type: 'flow', body: { text: body }, action: { name: 'flow', parameters: parameters } }
        request = stub_request(:post, graph_url).with(body: envelope(interactive).to_json).to_return(meta_ok)

        message = deliver(outgoing(conversation))

        expect(request).to have_been_requested.once
        expect(message.source_id).to eq('wamid.flow')
        expect(message.status).not_to eq('failed')
      end

      it 'sends the text header, the footer and the draft mode, and leaves the name out of the Meta payload' do
        framed = rich_message.merge(header: 'Proposta GTA', footer: 'Leva um minuto', mode: 'draft', name: 'Login do corretor')
        interactive = { type: 'flow', header: { type: 'text', text: 'Proposta GTA' }, body: { text: body },
                        footer: { text: 'Leva um minuto' }, action: { name: 'flow', parameters: parameters.merge(mode: 'draft') } }
        request = stub_request(:post, graph_url).with(body: envelope(interactive).to_json).to_return(meta_ok)

        deliver(outgoing(conversation, content_attributes: { rich_message: framed }))

        expect(request).to have_been_requested.once
      end

      it 'sends no data when it does not come' do
        without_data = rich_message.except(:data)
        interactive = { type: 'flow', body: { text: body },
                        action: { name: 'flow', parameters: parameters.merge(flow_action_payload: { screen: 'LOGIN' }) } }
        request = stub_request(:post, graph_url).with(body: envelope(interactive).to_json).to_return(meta_ok)

        deliver(outgoing(conversation, content_attributes: { rich_message: without_data }))

        expect(request).to have_been_requested.once
      end

      it 'keeps the form data and the token out of the application log, at every level, when Meta refuses the flow' do
        refusal = { error: { message: 'Flow not published', code: 100 } }.to_json
        stub_request(:post, graph_url).to_return(status: 400, body: refusal, headers: { 'Content-Type' => 'application/json' })
        message = outgoing(conversation)
        log = StringIO.new
        allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log, level: :debug))

        deliver(message)

        expect(message.status).to eq('failed')
        expect(message.external_error).to eq('Flow not published')
        expect(log.string).to include('Flow not published')
        expect(log.string).not_to include('01001000')
        expect(log.string).not_to include('sessao-1739999999-123456')
      end

      {
        'a blank body' => [{}, { content: '' }, described_class::BODY_BLANK],
        'a body above 1024 characters' => [{}, { content: 'a' * 1025 }, described_class::BODY_TOO_LONG],
        'a missing flow id' => [{ flow_id: nil }, {}, described_class::FLOW_ID_INVALID],
        'a flow id that is a JSON number' => [{ flow_id: 1_234_567_890 }, {}, described_class::FLOW_ID_INVALID],
        'a blank flow id' => [{ flow_id: ' ' }, {}, described_class::FLOW_ID_INVALID],
        'an empty flow id' => [{ flow_id: '' }, {}, described_class::FLOW_ID_INVALID],
        'a flow id with letters' => [{ flow_id: '12345abc' }, {}, described_class::FLOW_ID_INVALID],
        'a flow id with a space' => [{ flow_id: '123 456' }, {}, described_class::FLOW_ID_INVALID],
        'a flow id with a sign' => [{ flow_id: '-123456' }, {}, described_class::FLOW_ID_INVALID],
        'a missing button text' => [{ cta: nil }, {}, described_class::CTA_BLANK],
        'a button text above 30 characters' => [{ cta: 'a' * 31 }, {}, described_class::CTA_TOO_LONG],
        'a missing token' => [{ token: nil }, {}, described_class::TOKEN_INVALID],
        'a token that is not text' => [{ token: 42 }, {}, described_class::TOKEN_INVALID],
        'a missing screen' => [{ screen: nil }, {}, described_class::SCREEN_INVALID],
        'empty data' => [{ data: {} }, {}, described_class::DATA_INVALID],
        'data that is not an object' => [{ data: 'cep=01001000' }, {}, described_class::DATA_INVALID],
        'data that is a list' => [{ data: ['01001000'] }, {}, described_class::DATA_INVALID],
        'data above 8 KB' => [{ data: { 'x' => 'a' * 8185 } }, {}, described_class::DATA_TOO_LARGE],
        'a published mode written out' => [{ mode: 'published' }, {}, described_class::MODE_INVALID],
        'a header above 60 characters' => [{ header: 'a' * 61 }, {}, described_class::HEADER_INVALID],
        'a footer that is not text' => [{ footer: 7 }, {}, described_class::FOOTER_INVALID],
        'a blank name' => [{ name: ' ' }, {}, described_class::NAME_INVALID],
        'a name above 60 characters' => [{ name: 'a' * 61 }, {}, described_class::NAME_INVALID]
      }.each do |title, (rich_changes, message_changes, error)|
        it "fails the message without sending anything for #{title}" do
          message = outgoing(conversation, { content_attributes: { rich_message: rich_message.merge(rich_changes) } }.merge(message_changes))

          deliver(message)

          expect(message.status).to eq('failed')
          expect(message.external_error).to eq(error)
          expect(a_request(:post, graph_url)).not_to have_been_made
        end
      end

      it 'accepts the limits themselves (30 character button, 1024 character body, 60 character header, footer and name, 8 KB data)' do
        request = stub_request(:post, graph_url).to_return(meta_ok)
        data_at_the_limit = { 'x' => 'a' * 8184 }
        at_the_limit = rich_message.merge(cta: 'a' * 30, header: 'a' * 60, footer: 'a' * 60, name: 'a' * 60, data: data_at_the_limit)
        message = outgoing(conversation, content: 'a' * 1024, content_attributes: { rich_message: at_the_limit })

        expect(data_at_the_limit.to_json.bytesize).to eq(described_class::DATA_MAX)
        expect(deliver(message).status).to eq('sent')
        expect(request).to have_been_requested.once
      end

      it 'accepts an emoji in the button text, which Meta only advises against' do
        request = stub_request(:post, graph_url).to_return(meta_ok)

        message = deliver(outgoing(conversation, content_attributes: { rich_message: rich_message.merge(cta: 'Iniciar 👉') }))

        expect(message.status).to eq('sent')
        expect(request).to have_been_requested.once
      end
    end

    context 'when the 24h window is closed' do
      it 'fails with the named window error and sends nothing' do
        message = deliver(outgoing(conversation))

        expect(message.status).to eq('failed')
        expect(message.external_error).to eq(I18n.t('errors.whatsapp.message_outside_messaging_window'))
        expect(a_request(:post, graph_url)).not_to have_been_made
      end
    end

    context 'when an agent retries a failed flow', type: :request do
      let(:agent) { create(:user, account: inbox.account, role: :agent) }

      before do
        open_window(conversation)
        create(:inbox_member, inbox: inbox, user: agent)
      end

      it 'keeps the whole rich_message, token and data included, and sends again with the same flow_token' do
        message = outgoing(conversation, status: :failed,
                                         content_attributes: { rich_message: rich_message, external_error: 'Flow not published' })
        request = stub_request(:post, graph_url).with(
          body: hash_including('interactive' => hash_including('action' => hash_including(
            'parameters' => hash_including('flow_token' => 'sessao-1739999999-123456',
                                           'flow_action_payload' => { 'screen' => 'LOGIN', 'data' => data })
          )))
        ).to_return(meta_ok)

        post "/api/v1/accounts/#{inbox.account_id}/conversations/#{conversation.display_id}/messages/#{message.id}/retry",
             headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(message.reload.content_attributes).to eq('rich_message' => rich_message.deep_stringify_keys)

        expect(deliver(message).status).to eq('sent')
        expect(request).to have_been_requested.once
      end
    end

    context 'when the message is created through the API', type: :request do
      let(:agent) { create(:user, account: inbox.account, role: :administrator) }

      def create_message(rich)
        post api_v1_account_conversation_messages_url(account_id: inbox.account_id, conversation_id: conversation.display_id),
             params: { content: body, content_attributes: { rich_message: rich } }, headers: agent.create_new_auth_token, as: :json
      end

      it 'creates a valid flow' do
        expect { create_message(rich_message) }.to change(Message, :count).by(1)

        expect(response).to have_http_status(:success)
      end

      {
        'a flow id that is a JSON number' => [{ flow_id: 1_234_567_890 }, described_class::FLOW_ID_INVALID],
        'a flow id with letters' => [{ flow_id: '12ab' }, described_class::FLOW_ID_INVALID],
        'data above 8 KB' => [{ data: { 'x' => 'a' * 8185 } }, described_class::DATA_TOO_LARGE],
        'a missing token' => [{ token: nil }, described_class::TOKEN_INVALID]
      }.each do |title, (changes, error)|
        it "answers 422 with the reason and creates nothing for #{title}" do
          expect { create_message(rich_message.merge(changes)) }.not_to change(Message, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq(error)
        end
      end
    end
  end

  {
    'cta' => 'CTA_MULTILINE', 'flow_id' => 'FLOW_ID_INVALID', 'token' => 'TOKEN_INVALID', 'screen' => 'SCREEN_INVALID',
    'header' => 'HEADER_INVALID', 'footer' => 'FOOTER_INVALID', 'name' => 'NAME_INVALID'
  }.each do |field, error|
    it "refuses a #{field} with a line break" do
      flow = described_class.new(rich_message.stringify_keys.merge(field => "uma\nduas"))

      expect(flow.error_for(body)).to eq(described_class.const_get(error))
      expect(described_class.new(rich_message.stringify_keys.merge(field => "uma\rduas")).error_for(body)).to be_present
    end
  end

  context 'with a channel that is not the official WhatsApp' do
    it 'refuses the flow on a 360dialog WhatsApp inbox instead of sending only the body' do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      channel = create(:channel_whatsapp, sync_templates: false)
      contact_inbox = create(:contact_inbox, inbox: channel.inbox, source_id: '123456789')
      conversation = create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox)
      open_window(conversation)

      message = deliver(outgoing(conversation))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(RichMessages::NO_TEXT_VERSION)
      expect(a_request(:post, 'https://waba.360dialog.io/v1/messages')).not_to have_been_made
    end
  end
end
