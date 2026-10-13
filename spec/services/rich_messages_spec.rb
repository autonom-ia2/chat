require 'rails_helper'

# chat#1473: o encaixe dos envios ricos, provado com um tipo que só existe neste spec. Nada aqui (nem em `app/`)
# conhece um tipo específico: acrescentar um tipo é criar a classe dele em RichMessages::Types.
describe RichMessages do
  let(:spec_type) do
    Class.new do
      def initialize(payload)
        @code = payload['code']
      end

      def error_for(body)
        'Carimbo sem código.' if @code.blank? || body.blank?
      end

      def whatsapp_cloud_payload(body)
        { type: 'spec_stamp', spec_stamp: { code: @code, text: body } }
      end

      def fallback_text(body)
        "#{body} [#{@code}]"
      end
    end
  end
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, account: inbox.account) }
  let(:meta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.rico' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

  before do
    stub_const('RichMessages::Types::SpecStamp', spec_type)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: inbox.account)
  end

  def outgoing(rich_message, attrs = {})
    create(:message, { message_type: :outgoing, content: 'Corpo', conversation: conversation, inbox: inbox, account: inbox.account,
                       content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  def deliver(message)
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  it 'sends on WhatsApp Cloud whatever the type builds, in a single message' do
    request = stub_request(:post, meta_url)
              .with(body: { messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094',
                            type: 'spec_stamp', spec_stamp: { code: 'A1', text: 'Corpo' } }.to_json)
              .to_return(meta_ok)

    message = deliver(outgoing({ type: 'spec_stamp', code: 'A1' }))

    expect(request).to have_been_requested.once
    expect(message.source_id).to eq('wamid.rico')
  end

  it 'uses the fallback text of the type as the outgoing text' do
    message = outgoing({ type: 'spec_stamp', code: 'A1' })

    expect(message.outgoing_content).to eq('Corpo [A1]')
    expect(described_class.fallback_text(message)).to eq('Corpo [A1]')
    expect(described_class.body_text(message)).to eq('Corpo')
  end

  it 'fails the message with the error of the type, without sending' do
    message = deliver(outgoing({ type: 'spec_stamp' }))

    expect(message.status).to eq('failed')
    expect(message.external_error).to eq('Carimbo sem código.')
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'marks the message as failed with the error returned by Meta' do
    stub_request(:post, meta_url).to_return(status: 400, body: { error: { message: '(#100) Invalid parameter' } }.to_json,
                                            headers: { 'Content-Type' => 'application/json' })

    message = deliver(outgoing({ type: 'spec_stamp', code: 'A1' }))

    expect(message.status).to eq('failed')
    expect(message.external_error).to eq('(#100) Invalid parameter')
  end

  describe 'an unknown or unsafe type' do
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
      'a type that names a top-level class' => 'message',
      'a type that names Object' => 'object',
      'a type that names a class outside RichMessages::Types' => 'send_guard'
    }.each do |title, type|
      it "fails the message as an unknown format for #{title}" do
        message = deliver(outgoing({ type: type, code: 'A1' }))

        expect(described_class.type_class(type)).to be_nil
        expect(message.status).to eq('failed')
        expect(message.external_error).to eq(described_class::UNKNOWN_TYPE)
        expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
      end
    end

    it 'fails a rich_message that is not an object' do
      message = deliver(outgoing('spec_stamp'))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(described_class::UNKNOWN_TYPE)
    end

    it 'keeps the plain outgoing text' do
      expect(outgoing({ type: 'carousel' }).outgoing_content).to eq('Corpo')
    end
  end
end
