require 'rails_helper'

# chat#1473 (P5): a localização que o cliente manda pelo WhatsApp fica estruturada para o robô e o agente lerem,
# em `content_attributes.shared_location`, sem mudar o anexo de localização de antes.
describe RichMessages::ReceivedLocation do
  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:location) do
    { latitude: -23.5505, longitude: -46.6333, name: 'Praça da Sé', address: 'Praça da Sé, São Paulo - SP',
      url: 'https://foursquare.com/v/praca-da-se' }
  end

  def receive(location_payload, extra = {})
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: '5511900000001' }],
        messages: [{ from: '5511900000001', id: 'wamid.local-do-cliente', timestamp: '1760371920', type: 'location',
                     location: location_payload }.merge(extra)]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
    Message.find_by!(source_id: 'wamid.local-do-cliente')
  end

  it 'keeps latitude, longitude, name and address as separate fields' do
    message = receive(location)

    expect(message.content_attributes['shared_location']).to eq(
      'latitude' => -23.5505, 'longitude' => -46.6333, 'name' => 'Praça da Sé', 'address' => 'Praça da Sé, São Paulo - SP'
    )
  end

  it 'leaves the location attachment as it was' do
    attachment = receive(location).attachments.sole

    expect(attachment.file_type).to eq('location')
    expect(attachment.coordinates_lat).to eq(-23.5505)
    expect(attachment.coordinates_long).to eq(-46.6333)
    expect(attachment.fallback_title).to eq('Praça da Sé, Praça da Sé, São Paulo - SP')
    expect(attachment.external_url).to eq('https://foursquare.com/v/praca-da-se')
  end

  it 'keeps only the coordinates when the customer shares neither name nor address' do
    message = receive(location.slice(:latitude, :longitude))

    expect(message.content_attributes['shared_location']).to eq('latitude' => -23.5505, 'longitude' => -46.6333)
  end

  it 'keeps the address when it comes without a name (the attachment title loses it)' do
    message = receive(location.except(:name))

    expect(message.content_attributes['shared_location']['address']).to eq('Praça da Sé, São Paulo - SP')
    expect(message.attachments.sole.fallback_title).to eq('')
  end

  it 'delivers the structured location and the request it answers to the bot webhook' do
    conversation = create(:conversation, inbox: inbox, account: inbox.account,
                                         contact_inbox: create(:contact_inbox, inbox: inbox, source_id: '5511900000001'))
    request = create(:message, message_type: :outgoing, conversation: conversation, inbox: inbox, account: inbox.account,
                               content: 'Me envie onde você está.', source_id: 'wamid.pedido',
                               content_attributes: { rich_message: { type: 'location_request' } })

    message = receive(location, context: { from: channel.phone_number, id: 'wamid.pedido' })
    data = message.webhook_data

    expect(message.conversation).to eq(conversation)
    expect(data[:content_attributes]['in_reply_to']).to eq(request.id)
    expect(data[:content_attributes]['shared_location']).to include('latitude' => -23.5505, 'longitude' => -46.6333)
  end

  it 'adds nothing to a message that is not a location' do
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: '5511900000001' }],
        messages: [{ from: '5511900000001', id: 'wamid.texto', timestamp: '1760371920', type: 'text', text: { body: 'oi' } }]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform

    expect(Message.find_by!(source_id: 'wamid.texto').content_attributes).not_to have_key('shared_location')
  end

  context 'with a 360dialog inbox' do
    let(:channel) { create(:channel_whatsapp, sync_templates: false) }

    before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

    it 'keeps the structured location too' do
      params = {
        'contacts' => [{ 'profile' => { 'name' => 'Camila Duarte' }, 'wa_id' => '5511900000001' }],
        'messages' => [{ 'from' => '5511900000001', 'id' => 'wamid.local-360', 'timestamp' => '1760371920', 'type' => 'location',
                         'location' => location }]
      }.with_indifferent_access
      Whatsapp::IncomingMessageService.new(inbox: inbox, params: params).perform

      expect(Message.find_by!(source_id: 'wamid.local-360').content_attributes['shared_location'])
        .to include('latitude' => -23.5505, 'name' => 'Praça da Sé')
    end
  end
end
