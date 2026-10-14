require 'rails_helper'

# chat#1473 (P3): `content_attributes.rich_message` do tipo `options` (botões de resposta e lista).
describe RichMessages::Types::Options do
  let(:body) { 'Como você prefere continuar?' }
  let(:three) do
    [{ id: 'agendar', title: 'Agendar visita' }, { id: 'horarios', title: 'Ver horários' }, { id: 'pessoa', title: 'Falar com uma pessoa' }]
  end
  let(:four) { three + [{ id: 'sair', title: 'Encerrar' }] }
  let(:sections) do
    [{ title: 'Atendimento', options: [{ id: 'remarcar', title: 'Remarcar horário', description: 'Trocar o dia ou a hora' },
                                       { id: 'cancelar', title: 'Cancelar horário' }] },
     { title: 'Pagamento', options: [{ id: 'boleto', title: 'Segunda via do boleto' }] }]
  end

  def options(payload)
    described_class.new(payload.deep_stringify_keys)
  end

  def option_list(count, id_size: 4, title_size: 6)
    Array.new(count) { |index| { id: index.to_s.rjust(id_size, 'i'), title: index.to_s.rjust(title_size, 't') } }
  end

  it 'is the class of the options type' do
    expect(RichMessages.type_class('options')).to eq(described_class)
  end

  describe '#whatsapp_cloud_payload' do
    it 'turns up to 3 options into reply buttons' do
      payload = options(options: three, header: 'Próximo passo', footer: 'Toque em uma opção.').whatsapp_cloud_payload(body)

      expect(payload).to eq(
        type: 'interactive',
        interactive: {
          type: 'button',
          header: { type: 'text', text: 'Próximo passo' },
          body: { text: body },
          footer: { text: 'Toque em uma opção.' },
          action: { buttons: [
            { type: 'reply', reply: { id: 'agendar', title: 'Agendar visita' } },
            { type: 'reply', reply: { id: 'horarios', title: 'Ver horários' } },
            { type: 'reply', reply: { id: 'pessoa', title: 'Falar com uma pessoa' } }
          ] }
        }
      )
    end

    it 'leaves header and footer out when they do not come' do
      interactive = options(options: three.first(1)).whatsapp_cloud_payload(body)[:interactive]

      expect(interactive.keys).to eq(%i[type body action])
    end

    it 'turns more than 3 options into a list with one section titled by the list button' do
      interactive = options(options: four, button: 'Ver opções').whatsapp_cloud_payload(body)[:interactive]

      expect(interactive).to eq(
        type: 'list',
        body: { text: body },
        action: {
          button: 'Ver opções',
          sections: [{ title: 'Ver opções', rows: four.map { |option| option.slice(:id, :title) } }]
        }
      )
    end

    it 'sends sections, descriptions and the list button as given' do
      interactive = options(sections: sections, button: 'Ver assuntos', header: 'Assuntos').whatsapp_cloud_payload(body)[:interactive]

      expect(interactive).to eq(
        type: 'list',
        header: { type: 'text', text: 'Assuntos' },
        body: { text: body },
        action: {
          button: 'Ver assuntos',
          sections: [
            { title: 'Atendimento', rows: [{ id: 'remarcar', title: 'Remarcar horário', description: 'Trocar o dia ou a hora' },
                                           { id: 'cancelar', title: 'Cancelar horário' }] },
            { title: 'Pagamento', rows: [{ id: 'boleto', title: 'Segunda via do boleto' }] }
          ]
        }
      )
    end

    it 'uses a list even with few options when they come in sections or with a description' do
      in_sections = options(sections: [{ options: three.first(2) }], button: 'Ver').whatsapp_cloud_payload(body)[:interactive]
      described_option = three.first.merge(description: 'Na unidade mais perto')
      described = options(options: [described_option], button: 'Ver').whatsapp_cloud_payload(body)[:interactive]

      expect(in_sections).to include(type: 'list', action: hash_including(sections: [{ title: 'Ver', rows: three.first(2) }]))
      expect(described).to include(type: 'list')
      expect(described.dig(:action, :sections, 0, :rows, 0, :description)).to eq('Na unidade mais perto')
    end
  end

  describe '#fallback_text' do
    it 'numbers the options, one per line' do
      expect(options(options: three).fallback_text(body)).to eq("1. Agendar visita\n2. Ver horários\n3. Falar com uma pessoa")
    end

    it 'keeps the section titles and the descriptions, numbering across sections' do
      expect(options(sections: sections).fallback_text(body)).to eq(
        "Atendimento\n1. Remarcar horário - Trocar o dia ou a hora\n2. Cancelar horário\nPagamento\n3. Segunda via do boleto"
      )
    end
  end

  describe '#error_for' do
    it 'accepts every Meta limit itself' do
      button_limits = [{ id: 'i' * 256, title: 'b' * 20 }, { id: 'j', title: 'c' * 20 }]
      list_limits = Array.new(10) do |index|
        { title: "#{index}#{'s' * 23}", options: [{ id: "#{index}#{'i' * 199}", title: "#{index}#{'t' * 23}", description: 'd' * 72 }] }
      end

      expect(options(options: button_limits, header: 'h' * 60, footer: 'f' * 60).error_for('a' * 1024)).to be_nil
      expect(options(sections: list_limits, button: 'b' * 20, header: 'h' * 60, footer: 'f' * 60).error_for('a' * 4096)).to be_nil
    end

    it 'accepts one section without a title and sends it titled by the list button' do
      [{ title: '', options: four }, { title: ' ', options: four }, { options: four }].each do |section|
        untitled = options(sections: [section], button: 'Ver')

        expect(untitled.error_for(body)).to be_nil
        expect(untitled.whatsapp_cloud_payload(body).dig(:interactive, :action, :sections, 0, :title)).to eq('Ver')
      end
    end

    it 'keeps the title the caller gave to a single section' do
      titled = options(sections: [{ title: 'Unidades', options: four }], button: 'Ver')

      expect(titled.whatsapp_cloud_payload(body).dig(:interactive, :action, :sections, 0, :title)).to eq('Unidades')
    end

    ["\n", "\r", "\v", "\u0085", "\u2028", "\u2029"].each do |line_break|
      it "refuses a line break #{line_break.dump} in titles, header, footer, list button and section title" do
        expect(options(options: [{ id: 'sim', title: "Sim#{line_break}claro" }]).error_for(body)).to eq(described_class::TITLE_MULTILINE)
        expect(options(options: three, header: "a#{line_break}b").error_for(body)).to eq(described_class::HEADER_INVALID)
        expect(options(options: three, footer: "a#{line_break}b").error_for(body)).to eq(described_class::FOOTER_INVALID)
        expect(options(options: four, button: "a#{line_break}b").error_for(body)).to eq(described_class::LIST_BUTTON_INVALID)
        expect(options(sections: [{ title: "a#{line_break}b", options: four }], button: 'Ver').error_for(body))
          .to eq(described_class::SECTION_TITLE_INVALID)
      end
    end

    {
      'a blank body' => [{}, '', :BODY_BLANK],
      'a body above 1024 characters with buttons' => [{}, 'a' * 1025, :BUTTONS_BODY_TOO_LONG],
      'options and sections together' => [{ sections: [{ options: [{ id: 'x', title: 'X' }] }] }, nil, :OPTIONS_AND_SECTIONS],
      'no options' => [{ options: [] }, nil, :NO_OPTIONS],
      'options that are not a list' => [{ options: { id: 'a', title: 'A' } }, nil, :NO_OPTIONS],
      'an option that is not an object' => [{ options: ['Sim'] }, nil, :OPTION_INVALID],
      'an option without id' => [{ options: [{ title: 'Sim' }] }, nil, :OPTION_INVALID],
      'an option with a numeric id' => [{ options: [{ id: 1, title: 'Sim' }] }, nil, :OPTION_INVALID],
      'an option with a blank title' => [{ options: [{ id: 'sim', title: ' ' }] }, nil, :OPTION_INVALID],
      'a button title above 20 characters' => [{ options: [{ id: 'sim', title: 'a' * 21 }] }, nil, :BUTTON_TITLE_TOO_LONG],
      'a button id above 256 characters' => [{ options: [{ id: 'i' * 257, title: 'Sim' }] }, nil, :BUTTON_ID_TOO_LONG],
      'two options with the same id' => [{ options: [{ id: 'x', title: 'Sim' }, { id: 'x', title: 'Não' }] }, nil, :OPTION_ID_REPEATED],
      'two buttons with the same title' => [{ options: [{ id: 'a', title: 'Sim' }, { id: 'b', title: 'Sim' }] }, nil, :BUTTON_TITLE_REPEATED],
      'a header above 60 characters' => [{ header: 'h' * 61 }, nil, :HEADER_INVALID],
      'an image header' => [{ header: { type: 'image', link: 'https://exemplo.com.br/a.png' } }, nil, :HEADER_INVALID],
      'a footer with a line break' => [{ footer: "um\ndois" }, nil, :FOOTER_INVALID]
    }.each do |title, (changes, message_body, error)|
      it "refuses #{title}" do
        expect(options({ options: three }.merge(changes)).error_for(message_body.nil? ? body : message_body))
          .to eq(described_class.const_get(error))
      end
    end

    it 'ignores the list button when the options go as buttons, even if it would not fit a list' do
      buttons = options(options: three, button: "#{'b' * 21}\nx")

      expect(buttons.error_for(body)).to be_nil
      expect(buttons.whatsapp_cloud_payload(body).dig(:interactive, :action)).not_to have_key(:button)
    end

    {
      'a body above 4096 characters' => [{ options: [] }, 'a' * 4097, :LIST_BODY_TOO_LONG],
      'more than 10 options' => [{ options: [] }, nil, :TOO_MANY_OPTIONS],
      'a row title above 24 characters' => [{ options: [{ id: 'x', title: 'a' * 25 }] }, nil, :ROW_TITLE_TOO_LONG],
      'a row id above 200 characters' => [{ options: [{ id: 'i' * 201, title: 'X' }] }, nil, :ROW_ID_TOO_LONG],
      'a description above 72 characters' => [{ options: [{ id: 'x', title: 'X', description: 'd' * 73 }] }, nil, :DESCRIPTION_INVALID],
      'a description that is not text' => [{ options: [{ id: 'x', title: 'X', description: 7 }] }, nil, :DESCRIPTION_INVALID],
      'a missing list button' => [{ options: [], button: nil }, nil, :LIST_BUTTON_INVALID],
      'a list button above 20 characters' => [{ options: [], button: 'b' * 21 }, nil, :LIST_BUTTON_INVALID],
      'a list button with a line break' => [{ options: [], button: "Ver\nopções" }, nil, :LIST_BUTTON_INVALID]
    }.each do |title, (changes, message_body, error)|
      it "refuses on a list #{title}" do
        count = error == :TOO_MANY_OPTIONS ? 11 : 4
        list = changes[:options] + option_list(count - changes[:options].size)

        refused = options(options: list, button: changes.fetch(:button, 'Ver opções'))

        expect(refused.error_for(message_body || body)).to eq(described_class.const_get(error))
      end
    end

    {
      'sections that are not a list' => [{ title: 'A', options: [{ id: 'a', title: 'A' }] }, :SECTION_INVALID],
      'a section that is not an object' => [['A'], :SECTION_INVALID],
      'a section without options' => [[{ title: 'A', options: [] }], :SECTION_INVALID],
      'more than 10 sections' => [Array.new(11) { |index| { title: "S#{index}", options: [{ id: "o#{index}", title: 'X' }] } },
                                  :TOO_MANY_SECTIONS],
      'a section title missing with two sections' => [[{ options: [{ id: 'a', title: 'A' }] }, { title: 'B', options: [{ id: 'b', title: 'B' }] }],
                                                      :SECTION_TITLE_INVALID],
      'a section title above 24 characters' => [[{ title: 's' * 25, options: [{ id: 'a', title: 'A' }] }], :SECTION_TITLE_INVALID],
      'the same id in two sections' => [[{ title: 'A', options: [{ id: 'x', title: 'A' }] }, { title: 'B', options: [{ id: 'x', title: 'B' }] }],
                                        :OPTION_ID_REPEATED],
      'more than 10 options across sections' => [[{ title: 'A', options: Array.new(6) { |index| { id: "a#{index}", title: 'A' } } },
                                                  { title: 'B', options: Array.new(5) { |index| { id: "b#{index}", title: 'B' } } }],
                                                 :TOO_MANY_OPTIONS]
    }.each do |title, (given_sections, error)|
      it "refuses in sections #{title}" do
        expect(options(sections: given_sections).error_for(body)).to eq(described_class.const_get(error))
      end
    end
  end

  context 'with a WhatsApp Cloud inbox' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
    let(:meta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
    let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.opcoes' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

    def outgoing(rich_message, content: body)
      create(:message, message_type: :outgoing, content: content, conversation: conversation, inbox: inbox, account: inbox.account,
                       content_attributes: { rich_message: rich_message })
    end

    def deliver(message)
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      message.reload
    end

    context 'when the 24h window is open' do
      before { create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: inbox.account) }

      it 'sends body and buttons in one interactive message' do
        interactive = { type: 'button', body: { text: body },
                        action: { buttons: three.map { |option| { type: 'reply', reply: option } } } }
        request = stub_request(:post, meta_url)
                  .with(body: { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094',
                                type: 'interactive', interactive: interactive }.to_json)
                  .to_return(meta_ok)

        message = deliver(outgoing({ type: 'options', options: three }))

        expect(request).to have_been_requested.once
        expect(message.source_id).to eq('wamid.opcoes')
        expect(message.status).not_to eq('failed')
      end

      it 'sends body, button and every section with its rows in one interactive list message' do
        interactive = {
          type: 'list', body: { text: body },
          action: {
            button: 'Ver assuntos',
            sections: [
              { title: 'Atendimento', rows: [{ id: 'remarcar', title: 'Remarcar horário', description: 'Trocar o dia ou a hora' },
                                             { id: 'cancelar', title: 'Cancelar horário' }] },
              { title: 'Pagamento', rows: [{ id: 'boleto', title: 'Segunda via do boleto' }] }
            ]
          }
        }
        request = stub_request(:post, meta_url)
                  .with(body: { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094',
                                type: 'interactive', interactive: interactive }.to_json)
                  .to_return(meta_ok)

        expect(deliver(outgoing({ type: 'options', sections: sections, button: 'Ver assuntos' })).status).not_to eq('failed')
        expect(request).to have_been_requested.once
      end

      it 'fails with the reason and sends nothing when the options break a Meta limit' do
        message = deliver(outgoing({ type: 'options', options: [{ id: 'sim', title: 'a' * 21 }] }))

        expect(message.status).to eq('failed')
        expect(message.external_error).to eq(described_class::BUTTON_TITLE_TOO_LONG)
        expect(a_request(:post, meta_url)).not_to have_been_made
      end
    end

    it 'fails with the named window error when the 24h window is closed' do
      message = deliver(outgoing({ type: 'options', options: three }))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(I18n.t('errors.whatsapp.message_outside_messaging_window'))
      expect(a_request(:post, meta_url)).not_to have_been_made
    end
  end

  context 'with a channel without interactive messages (360dialog)' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '123456789') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }

    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox, account: conversation.account)
    end

    it 'sends the body and the numbered options as text' do
      text = "#{body}\n\n1. Agendar visita\n2. Ver horários\n3. Falar com uma pessoa"
      request = stub_request(:post, 'https://waba.360dialog.io/v1/messages')
                .with(body: { 'to' => '123456789', 'text' => { 'body' => text }, 'type' => 'text' }.to_json)
                .to_return(status: 200, body: { 'messages' => [{ 'id' => 'd360' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      message = create(:message, message_type: :outgoing, content: body, conversation: conversation, inbox: channel.inbox,
                                 account: conversation.account, content_attributes: { rich_message: { type: 'options', options: three } })

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_requested.once
      expect(message.reload.status).not_to eq('failed')
    end
  end

  it 'escapes the options where the outgoing text is HTML (Telegram)' do
    channel = create(:channel_telegram)
    conversation = create(:conversation, inbox: channel.inbox, account: channel.account)
    message = create(:message, message_type: :outgoing, content: body, conversation: conversation, inbox: channel.inbox,
                               account: channel.account,
                               content_attributes: { rich_message: { type: 'options', options: [{ id: 'a', title: 'Sim <já>' }] } })

    expect(message.outgoing_content).to eq("#{body}\n\n1. Sim &lt;já&gt;")
  end
end
