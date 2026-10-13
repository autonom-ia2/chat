require 'rails_helper'

# chat#1473: a caixa Channel::Api (WhatsApp API/WAHA) é entregue pelo webhook da caixa, com o `content` cru.
# Mensagem com `rich_message` leva o texto de reserva nesse webhook, e só nele.
describe RichMessages::ApiInboxWebhook do
  let(:listener) { WebhookListener.instance }
  let(:channel) { create(:channel_api, webhook_url: 'https://bridge.example.com/hook') }
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:link) { 'https://exemplo.com.br/p?a=1&b=2' }
  let(:rich_message) { { type: 'link_button', label: 'Abrir <aqui>', url: link } }

  before { create(:webhook, account: account, inbox: inbox, subscriptions: %w[message_created message_updated]) }

  def outgoing(attrs = {})
    create(:message, { message_type: :outgoing, content: 'Corpo', conversation: conversation, inbox: inbox, account: account,
                       content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  def inbox_webhook_payloads(event_method, message)
    payloads = { inbox: [], account: [] }
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| payloads[kind == :api_inbox_webhook ? :inbox : :account] << payload }
    listener.public_send(event_method, Events::Base.new(event_method, Time.zone.now, message: message))
    payloads
  end

  %i[message_created message_updated].each do |event_method|
    describe "##{event_method}" do
      it 'delivers body and link as the content of the inbox webhook, leaving the account webhook untouched' do
        payloads = inbox_webhook_payloads(event_method, outgoing)

        expect(payloads[:inbox].map { |payload| payload[:content] }).to eq(["Corpo\n\nAbrir <aqui>: #{link}"])
        expect(payloads[:account].map { |payload| payload[:content] }).to eq(['Corpo'])
      end

      it 'does not deliver an invalid rich_message to the inbox webhook and fails the message with the reason' do
        message = outgoing(content_attributes: { rich_message: rich_message.merge(url: 'exemplo.com.br') })

        payloads = inbox_webhook_payloads(event_method, message)

        expect(payloads[:inbox]).to be_empty
        expect(message.reload.status).to eq('failed')
        expect(message.external_error).to eq(RichMessages::Types::LinkButton::INVALID_URL)
      end

      it 'leaves a message without rich_message untouched' do
        payloads = inbox_webhook_payloads(event_method, outgoing(content_attributes: {}))

        expect(payloads[:inbox].map { |payload| payload[:content] }).to eq(['Corpo'])
      end

      it 'delivers the real payload of a message whose content_attributes was never written, without loading it again' do
        message = outgoing(content_attributes: {})
        message.update_column(:content_attributes, nil) # rubocop:disable Rails/SkipsModelValidations
        message = Message.find(message.id)
        allow(Message).to receive(:find_by).and_call_original

        expect(message.webhook_data[:content_attributes]).to eq({})
        expect(inbox_webhook_payloads(event_method, message)[:inbox].map { |payload| payload[:content] }).to eq(['Corpo'])
        expect(Message).not_to have_received(:find_by)
      end

      it 'reads rich_message from the real payload, whose keys are strings' do
        payload = outgoing.webhook_data

        expect(payload[:content_attributes].keys).to eq(['rich_message'])
        expect(payload[:content_attributes]).to be_key(RichMessages::KEY)
      end

      it 'follows the original delivery when the message was deleted before the event ran' do
        message = outgoing
        payload_source = Message.find(message.id)
        message.delete

        payloads = inbox_webhook_payloads(event_method, payload_source)

        expect(payloads[:inbox].map { |payload| payload[:content] }).to eq(['Corpo'])
      end

      it 'fails an invalid message once: the event of that update does not write it again' do
        message = outgoing(content_attributes: { rich_message: { type: 'carousel' } })
        inbox_webhook_payloads(event_method, message)
        failed_at = message.reload.updated_at

        payloads = travel_to(1.minute.from_now) { inbox_webhook_payloads(:message_updated, message) }

        expect(payloads[:inbox]).to be_empty
        expect(message.reload.updated_at).to eq(failed_at)
      end

      it 'leaves a private note with an invalid rich_message untouched' do
        message = outgoing(private: true, content_attributes: { rich_message: { type: 'carousel' } })

        inbox_webhook_payloads(event_method, message)

        expect(message.reload.status).not_to eq('failed')
      end
    end
  end

  it 'fails a type without a text version instead of delivering only the body' do
    stub_const('RichMessages::Types::SpecMute', Class.new do
      def initialize(_payload); end
      def error_for(_body); end
      def whatsapp_cloud_payload(_body) = {}
      def fallback_text(_body); end
    end)
    message = outgoing(content_attributes: { rich_message: { type: 'spec_mute' } })

    payloads = inbox_webhook_payloads(:message_created, message)

    expect(payloads[:inbox]).to be_empty
    expect(message.reload.external_error).to eq(RichMessages::NO_TEXT_VERSION)
  end
end
