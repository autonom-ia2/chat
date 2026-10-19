require 'rails_helper'

# chat#1709 (fase 3): na caixa WAHA comum, com a flag, o `message_created` leva ao conector o texto já no formato do
# WhatsApp (`waha_text`, só com o renderer do chat#1740) e o pedido de mandar foto e vídeo como mídia
# (`waha_media_as_media`). Nada é gravado.
describe Waha::RichNative::OutgoingHints do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }

  def inbox_payload(message, event: :message_created)
    payloads = []
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| payloads << payload if kind == :api_inbox_webhook }
    WebhookListener.instance.public_send(event, Events::Base.new(event, Time.zone.now, message: message))
    payloads.sole
  end

  def outgoing(content, attributes = {})
    create(:message, message_type: :outgoing, content: content, conversation: conversation, inbox: inbox, account: account,
                     content_attributes: attributes)
  end

  def with_image(message, content_type)
    message.attachments.create!(account_id: account.id, file_type: :image,
                                file: { io: StringIO.new('x'), filename: 'foto', content_type: content_type })
    message
  end

  # Marca o texto que iria ao renderer, sem depender de qual renderer está no código.
  def stub_ready_renderer
    allow(described_class).to receive_messages(renderer_ready?: true)
    allow(described_class).to receive(:whatsapp_text) { |text, _message = nil| "WA[#{text}]" }
  end

  it 'adds nothing without the flag, as in main' do
    attributes = inbox_payload(with_image(outgoing('**oi**'), 'image/webp'))[:content_attributes]

    expect(attributes.keys & %w[waha_text waha_media_as_media]).to eq([])
  end

  context 'with the flag' do
    before { account.enable_features!(Waha::RichNative::FLAG) }

    it 'does not send waha_text while the chat#1740 renderer is not in the code (the connector keeps formatting)' do
      allow(described_class).to receive(:renderer_ready?).and_return(false)

      payload = inbox_payload(with_image(outgoing('~~x~~ e ```bloco```'), 'image/webp'))

      expect(payload[:content_attributes]).not_to have_key('waha_text')
      expect(payload[:content_attributes]).to include('waha_media_as_media' => true)
    end

    it 'sends the text rendered for WhatsApp, keeping the content' do
      stub_ready_renderer
      payload = inbox_payload(outgoing("**oi**\n\n- item"))

      expect(payload[:content]).to eq("**oi**\n\n- item")
      expect(payload[:content_attributes]['waha_text']).to eq("WA[**oi**\n\n- item]")
    end

    it 'uses the body plus the text version of a rich message that goes as text' do
      stub_ready_renderer
      options = { 'type' => 'options', 'options' => [{ 'id' => 'a', 'title' => 'Manhã' }, { 'id' => 'b', 'title' => 'Tarde' }] }
      payload = inbox_payload(outgoing('Qual horário?', 'rich_message' => options))

      expect(payload[:content_attributes]['waha_text']).to eq("WA[Qual horário?\n\n1. Manhã\n2. Tarde]")
    end

    it 'keeps the numbered options in the text of a NATIVE rich message (what the connector sends when the engine refuses)' do
      stub_ready_renderer
      poll = { 'type' => 'poll', 'options' => [{ 'id' => 'sim', 'title' => 'Sim' }, { 'id' => 'nao', 'title' => 'Não' }] }
      message = outgoing('Vem amanhã?', 'rich_message' => poll)
      message.update!(content_attributes: message.content_attributes.merge(RichMessages::SENT_AS_KEY => 'native'))

      payload = inbox_payload(message)

      expect(Waha::RichNative.sent_native?(message.reload)).to be(true)
      expect(payload[:content_attributes]['waha_text']).to eq("WA[Vem amanhã?\n\n1. Sim\n2. Não]")
    end

    it 'asks for media as media when there is a photo or a video' do
      stub_ready_renderer
      payload = inbox_payload(with_image(outgoing('legenda'), 'image/webp'))

      expect(payload[:content_attributes]).to include('waha_media_as_media' => true, 'waha_text' => 'WA[legenda]')
    end

    it 'adds nothing to private notes, incoming messages or updates' do
      stub_ready_renderer
      note = create(:message, message_type: :outgoing, private: true, content: 'nota', conversation: conversation, inbox: inbox,
                              account: account)
      updated = outgoing('editada')

      expect(inbox_payload(note)[:content_attributes]).not_to have_key('waha_text')
      expect(inbox_payload(updated, event: :message_updated)[:content_attributes]).not_to have_key('waha_text')
    end
  end

  it 'never stores the hints, whoever creates the message' do
    message = outgoing('oi', 'waha_text' => 'forjado', 'waha_media_as_media' => true, 'waha_native' => { 'kind' => 'sendList' })

    expect(message.reload.content_attributes.keys & %w[waha_text waha_media_as_media waha_native]).to eq([])
  end

  # Paridade com o conversor do conector (markdown.test.ts) e os 10 casos do item 8: só roda com o renderer do
  # chat#1740 no código (antes dele, o `waha_text` não sai, como provado acima). Saídas conferidas no renderer do
  # #1740 (commit 2fe40617) em 16/10/2026.
  describe 'parity with the connector formatting (chat#1740 renderer)' do
    before { skip('the chat#1740 WhatsApp renderer is not on this branch yet') unless described_class.renderer_ready? }

    {
      '```code block```' => '```code block```',
      '*italic* **bold**' => '_italic_ *bold*',
      "Hi \\\ntext message \\\nwith line \\\nbreak" => "Hi \ntext message \nwith line \nbreak",
      'https://example.com/page__name__test' => 'https://example.com/page__name__test',
      'Veja **isso** em https://example.com/test_link e _aquilo_' => 'Veja *isso* em https://example.com/test_link e _aquilo_',
      '~x~' => '~x~',
      '~~x~~' => '~x~',
      '`x`' => '`x`',
      "```\nlinha 1\nlinha 2\n```" => "```linha 1\nlinha 2```",
      '    recuado' => 'recuado',
      '2*3*4 e a**b**c' => '2*3*4 e a**b**c',
      "> um\n> dois\n> três" => "> um\n> dois\n> três",
      '[t](https://exemplo.com)' => 'https://exemplo.com',
      "\\* e \\- e fim \\\nlinha" => "* e - e fim \nlinha"
    }.each do |input, expected|
      it("renders #{input.inspect}") { expect(described_class.whatsapp_text(input)).to eq(expected) }
    end
  end
end
