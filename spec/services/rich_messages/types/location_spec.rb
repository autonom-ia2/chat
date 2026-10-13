require 'rails_helper'

# chat#1473 (P5): `content_attributes.rich_message` do tipo `location` (enviar um ponto no mapa).
describe RichMessages::Types::Location do
  let(:rich_message) do
    { type: 'location', latitude: -23.5489, longitude: -46.6388, name: 'Unidade Centro',
      address: 'Rua das Flores, 123, sala 45 - Centro, São Paulo - SP' }
  end
  let(:map_link) { 'https://maps.google.com/?q=-23.5489,-46.6388' }
  let(:text_version) { "Unidade Centro\nRua das Flores, 123, sala 45 - Centro, São Paulo - SP\n#{map_link}" }
  let(:meta_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }
  let(:meta_ok) { { status: 200, body: { messages: [{ id: 'wamid.local' }] }.to_json, headers: { 'Content-Type' => 'application/json' } } }

  def location(changes = {})
    described_class.new(rich_message.merge(changes).stringify_keys)
  end

  def outgoing(conversation, attrs = {})
    create(:message, { message_type: :outgoing, content: nil, conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account, content_attributes: { rich_message: rich_message } }.merge(attrs))
  end

  it 'is the class of the location type' do
    expect(RichMessages.type_class('location')).to eq(described_class)
  end

  describe 'text version' do
    it 'has the name, the address and a map link built from the coordinates' do
      expect(location.fallback_text('')).to eq(text_version)
    end

    it 'has only the map link without name and address' do
      expect(location(name: nil, address: nil).fallback_text('')).to eq(map_link)
    end

    it 'writes the coordinates in plain decimal notation, never in scientific notation' do
      expect(location(latitude: 0.00001, longitude: 10, name: nil, address: nil).fallback_text(''))
        .to eq('https://maps.google.com/?q=0.00001,10.0')
    end
  end

  describe 'Meta payload' do
    it 'sends the coordinates as decimal text and the optional name and address' do
      expect(location.whatsapp_cloud_payload('')).to eq(
        type: 'location',
        location: { latitude: '-23.5489', longitude: '-46.6388', name: 'Unidade Centro',
                    address: 'Rua das Flores, 123, sala 45 - Centro, São Paulo - SP' }
      )
    end

    it 'leaves out name and address when they do not come' do
      expect(location(name: nil, address: nil).whatsapp_cloud_payload(''))
        .to eq(type: 'location', location: { latitude: '-23.5489', longitude: '-46.6388' })
    end
  end

  describe 'validation' do
    it 'accepts the edges of the ranges and integer coordinates' do
      expect(location(latitude: -90, longitude: 180).error_for('')).to be_nil
      expect(location(latitude: 90.0, longitude: -180.0).error_for(nil)).to be_nil
    end

    it 'accepts name of 100 and address of 300 characters' do
      expect(location(name: 'a' * 100, address: 'a' * 300).error_for('')).to be_nil
    end

    {
      'a body' => [{}, 'Olá', 'BODY_NOT_ALLOWED'],
      'a missing latitude' => [{ latitude: nil }, '', 'LATITUDE_INVALID'],
      'a latitude in text' => [{ latitude: '-23.5' }, '', 'LATITUDE_INVALID'],
      'a latitude that is true' => [{ latitude: true }, '', 'LATITUDE_INVALID'],
      'a latitude above 90' => [{ latitude: 90.0001 }, '', 'LATITUDE_INVALID'],
      'a latitude below -90' => [{ latitude: -91 }, '', 'LATITUDE_INVALID'],
      'a missing longitude' => [{ longitude: nil }, '', 'LONGITUDE_INVALID'],
      'a longitude in text' => [{ longitude: '-46.6' }, '', 'LONGITUDE_INVALID'],
      'a longitude above 180' => [{ longitude: 180.5 }, '', 'LONGITUDE_INVALID'],
      'a longitude below -180' => [{ longitude: -181 }, '', 'LONGITUDE_INVALID'],
      'a blank name' => [{ name: ' ' }, '', 'NAME_INVALID'],
      'a name that is not text' => [{ name: 7 }, '', 'NAME_INVALID'],
      'a name above 100 characters' => [{ name: 'a' * 101 }, '', 'NAME_INVALID'],
      'a name with a line break' => [{ name: "Unidade\nCentro" }, '', 'NAME_INVALID'],
      'a blank address' => [{ address: '' }, '', 'ADDRESS_INVALID'],
      'an address above 300 characters' => [{ address: 'a' * 301 }, '', 'ADDRESS_INVALID'],
      'an address with a line break' => [{ address: "Rua A\rCentro" }, '', 'ADDRESS_INVALID']
    }.each do |title, (changes, body, error)|
      it "refuses #{title}" do
        expect(location(changes).error_for(body)).to eq(described_class.const_get(error))
      end
    end
  end

  context 'with a WhatsApp Cloud inbox and the 24h window open' do
    let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
    let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox, account: inbox.account) }

    def deliver(message)
      Whatsapp::SendOnWhatsappService.new(message: message).perform
      message.reload
    end

    before do
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: inbox.account)
    end

    it 'sends one location message with the exact payload' do
      expected = {
        messaging_product: 'whatsapp', recipient_type: 'individual', to: '5511937016094', type: 'location',
        location: { latitude: '-23.5489', longitude: '-46.6388', name: 'Unidade Centro',
                    address: 'Rua das Flores, 123, sala 45 - Centro, São Paulo - SP' }
      }
      request = stub_request(:post, meta_url).with(body: expected.to_json).to_return(meta_ok)

      message = deliver(outgoing(conversation))

      expect(request).to have_been_requested.once
      expect(message.source_id).to eq('wamid.local')
      expect(message.status).not_to eq('failed')
    end

    it 'fails a message with a body, instead of sending two messages or dropping the body' do
      message = deliver(outgoing(conversation, content: 'Nossa unidade:'))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(described_class::BODY_NOT_ALLOWED)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'fails invalid coordinates without sending anything' do
      message = deliver(outgoing(conversation, content_attributes: { rich_message: rich_message.merge(latitude: 123) }))

      expect(message.status).to eq('failed')
      expect(message.external_error).to eq(described_class::LATITUDE_INVALID)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  context 'with a WhatsApp inbox from another provider (360dialog)' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }
    let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '123456789') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: channel.inbox) }

    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
      create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: conversation.inbox,
                       account: conversation.account)
    end

    it 'sends name, address and map link as text' do
      request = stub_request(:post, 'https://waba.360dialog.io/v1/messages')
                .with(body: { 'to' => '123456789', 'text' => { 'body' => text_version }, 'type' => 'text' }.to_json)
                .to_return(status: 200, body: { 'messages' => [{ 'id' => 'd360' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

      message = outgoing(conversation)
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(request).to have_been_requested.once
      expect(message.reload.status).not_to eq('failed')
    end
  end

  it 'escapes the text version on Telegram, whose outgoing text is HTML' do
    channel = create(:channel_telegram)
    conversation = create(:conversation, inbox: channel.inbox, account: channel.account)
    message = outgoing(conversation, content_attributes: { rich_message: rich_message.merge(name: 'Loja <Centro> & cia', address: nil) })

    expect(message.outgoing_content).to eq("Loja &lt;Centro&gt; &amp; cia\n#{map_link}")
  end
end
