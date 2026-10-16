require 'rails_helper'

# chat#1709 (fase 3): na caixa WAHA comum, com a flag, o `message_created` leva ao conector o texto já no formato do
# WhatsApp (`waha_text`) e o pedido de mandar foto e vídeo como mídia (`waha_media_as_media`). Nada é gravado.
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

  it 'adds nothing without the flag, as in main' do
    attributes = inbox_payload(with_image(outgoing('**oi**'), 'image/webp'))[:content_attributes]

    expect(attributes.keys & %w[waha_text waha_media_as_media]).to eq([])
  end

  context 'with the flag' do
    before { account.enable_features!(Waha::RichNative::FLAG) }

    it 'sends the text rendered for WhatsApp by the same renderer as the Cloud, keeping the content' do
      payload = inbox_payload(outgoing("**oi**\n\n- item"))

      expect(payload[:content]).to eq("**oi**\n\n- item")
      expect(payload[:content_attributes]['waha_text'])
        .to eq(Messages::MarkdownRendererService.new("**oi**\n\n- item", 'Channel::Whatsapp').render)
    end

    it 'uses the body plus the text version of a rich message that goes as text' do
      options = { 'type' => 'options', 'options' => [{ 'id' => 'a', 'title' => 'Manhã' }, { 'id' => 'b', 'title' => 'Tarde' }] }
      payload = inbox_payload(outgoing('Qual horário?', 'rich_message' => options))

      expect(payload[:content_attributes]['waha_text']).to eq("Qual horário?\n\n1. Manhã\n2. Tarde")
    end

    it 'asks for media as media when there is a photo or a video' do
      payload = inbox_payload(with_image(outgoing('legenda'), 'image/webp'))

      expect(payload[:content_attributes]).to include('waha_media_as_media' => true, 'waha_text' => 'legenda')
    end

    it 'adds nothing to private notes, incoming messages or updates' do
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
end
