require 'rails_helper'

# chat#1709 (fase 3): `content_attributes.rich_message` do tipo `poll` (enquete). Só existe com a flag
# `whatsapp_rich_native` (Waha::RichNative::PollGate); na Cloud sai como texto numerado.
describe RichMessages::Types::Poll do
  let(:options) { [{ 'id' => 'sim', 'title' => 'Sim' }, { 'id' => 'nao', 'title' => 'Não' }] }
  let(:payload) { { 'type' => 'poll', 'options' => options } }

  def error(body: 'Vem amanhã?', **changes)
    described_class.new(payload.merge(changes.stringify_keys)).error_for(body)
  end

  it 'is the class of the poll type, with a numbered text version' do
    expect(RichMessages.type_class('poll')).to eq(described_class)
    expect(described_class.new(payload).fallback_text('Vem amanhã?')).to eq("1. Sim\n2. Não")
    expect(described_class.new(payload.merge('multiple' => false)).fallback_text('Vem amanhã?')).to eq("1. Sim\n2. Não")
  end

  it 'adds the "more than one" line to the text version when multiple is true, in the given locale' do
    poll = described_class.new(payload.merge('multiple' => true), locale: 'pt_BR')
    expect(poll.fallback_text('Vem amanhã?')).to eq("1. Sim\n2. Não\nPode escolher mais de uma")
    expect(poll.whatsapp_cloud_payload('Vem amanhã?')[:text][:body])
      .to eq("Vem amanhã?\n\n1. Sim\n2. Não\nPode escolher mais de uma")
    expect(described_class.new(payload.merge('multiple' => true), locale: 'en').fallback_text('Vem amanhã?'))
      .to eq("1. Sim\n2. Não\nYou can choose more than one")
  end

  # O aviso vai ao cliente: o formato montado pela mensagem (RichMessages.build, via Waha::RichNative::PollGate) usa o
  # idioma da conta.
  describe 'the text version of a message, in the account locale' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    def text_of(locale)
      account.update!(locale: locale)
      message = Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                            content: 'Vem amanhã?', content_attributes: { 'rich_message' => payload.merge('multiple' => true) })
      RichMessages.text_with_fallback(message, message.content)
    end

    it 'goes in Portuguese to a pt_BR account and in English to an en account, numbering intact' do
      expect(text_of('pt_BR')).to eq("Vem amanhã?\n\n1. Sim\n2. Não\nPode escolher mais de uma")
      expect(text_of('en')).to eq("Vem amanhã?\n\n1. Sim\n2. Não\nYou can choose more than one")
    end
  end

  # Enviada como texto (Cloud, grupo, motor sem enquete), o cliente responde pelo número ("2", "1 e 3"). Quem casa a
  # resposta com a opção é o modelo, que lê esse texto: o número N tem de continuar sendo a opção N, e a linha do
  # aviso não pode virar opção.
  it 'keeps the numbering of a multiple-answer poll sent as text: number N is option N, the hint is no option' do
    three = options + [{ 'id' => 'talvez', 'title' => 'Talvez' }]
    poll = described_class.new(payload.merge('options' => three, 'multiple' => true), locale: 'pt_BR')
    lines = poll.fallback_text('Vem amanhã?').split("\n")
    hint = 'Pode escolher mais de uma'

    numbered = lines.reject { |line| line == hint }
    expect(numbered.size).to eq(three.size)
    three.each.with_index(1) do |option, number|
      expect(lines.find { |line| line.start_with?("#{number}. ") }).to eq("#{number}. #{option['title']}")
    end
    expect(lines.last).to eq(hint)
    expect(lines.count { |line| line.start_with?("#{three.size + 1}.") }).to eq(0)
    expect(hint.start_with?(*('0'..'9').to_a)).to be(false)
  end

  it 'goes to the Cloud API as text, question and options' do
    expect(described_class.new(payload).whatsapp_cloud_payload('Vem amanhã?'))
      .to eq(type: 'text', text: { body: "Vem amanhã?\n\n1. Sim\n2. Não", preview_url: false })
  end

  it 'accepts the engine limits' do
    expect(error).to be_nil
    expect(error(options: Array.new(12) { |i| { 'id' => "o#{i}", 'title' => "Opção #{i}" } })).to be_nil
    expect(error(multiple: true)).to be_nil
    expect(error(body: 'x' * 255)).to be_nil
  end

  it 'refuses a missing or long question and a wrong number of options' do
    expect(error(body: '')).to eq(described_class::BODY_INVALID)
    expect(error(body: 'x' * 256)).to eq(described_class::BODY_INVALID)
    expect(error(options: options.first(1))).to eq(described_class::OPTIONS_INVALID)
    expect(error(options: Array.new(13) { |i| { 'id' => "o#{i}", 'title' => "O#{i}" } })).to eq(described_class::OPTIONS_INVALID)
    expect(error(options: 'Sim')).to eq(described_class::OPTIONS_INVALID)
    expect(error(multiple: 'yes')).to eq(described_class::MULTIPLE_INVALID)
  end

  it 'refuses each option outside the contract' do
    invalid = {
      [{ 'id' => 'a' }] => described_class::OPTION_INVALID,
      [{ 'id' => 'a|1', 'title' => 'A' }] => described_class::ID_INVALID,
      [{ 'id' => 'a' * 201, 'title' => 'A' }] => described_class::ID_INVALID,
      [{ 'id' => 'a', 'title' => 'A' * 101 }] => described_class::TITLE_INVALID,
      [{ 'id' => 'a', 'title' => "A\nB" }] => described_class::TITLE_INVALID,
      [{ 'id' => 'b', 'title' => 'A' }] => described_class::ID_REPEATED,
      [{ 'id' => 'a', 'title' => ' B ' }] => described_class::TITLE_REPEATED
    }
    invalid.each do |first, reason|
      expect(error(options: first + [{ 'id' => 'b', 'title' => 'B' }])).to eq(reason), first.inspect
    end
  end

  describe 'the flag gate (Waha::RichNative::PollGate)' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:account) { inbox.account }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, account: account) }

    def draft
      Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Vem amanhã?',
                  content_attributes: { 'rich_message' => payload })
    end

    it 'is an unknown type without the flag, as in main' do
      expect(RichMessages.format_error(draft)).to eq(RichMessages::UNKNOWN_TYPE)
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'poll', conversation: conversation)).to eq(:refused)
    end

    it 'exists with the flag, and goes as text on the Cloud even with the window open' do
      account.enable_features!(Waha::RichNative::FLAG)
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: account)

      expect(RichMessages.format_error(draft)).to be_nil
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'poll', conversation: conversation)).to eq(:text)
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:native)
    end

    it 'sends the numbered text through the Cloud and marks the message as sent as text' do
      account.enable_features!(Waha::RichNative::FLAG)
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: account)
      request = stub_request(:post, 'https://graph.facebook.com/v22.0/123456789/messages')
                .with(body: hash_including('type' => 'text', 'text' => { 'body' => "Vem amanhã?\n\n1. Sim\n2. Não", 'preview_url' => false }))
                .to_return(status: 200, body: { messages: [{ id: 'wamid.poll' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      message = create(:message, message_type: :outgoing, content: 'Vem amanhã?', conversation: conversation, inbox: inbox,
                                 account: account, content_attributes: { rich_message: payload })

      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_made.once
      expect(message.reload.content_attributes).to include('rich_message_sent_as' => 'text',
                                                           'rich_message_sent_text' => "Vem amanhã?\n\n1. Sim\n2. Não")
    end
  end
end
