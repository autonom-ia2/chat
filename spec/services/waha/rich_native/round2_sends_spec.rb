require 'rails_helper'
require_relative '../../whatsapp_hybrid/rich_native_context'

# chat#1709 (rodada 2): botão de link como cartão de prévia e convite de evento pelo motor WAHA, com a resposta de volta.
describe 'WAHA rich native round 2 sends' do # rubocop:disable RSpec/DescribeClass
  let(:engine_client) { instance_double(Waha::Client) }
  let(:start_at) { Time.find_zone('America/Sao_Paulo').now.advance(days: 2).change(hour: 14, min: 0, sec: 0) }
  let(:event_rich) do
    { type: 'event', start_at: start_at.iso8601, end_at: (start_at + 1.hour).iso8601, location_name: 'Av. Paulista, 1000',
      description: 'Vistoria do carro' }
  end

  def payload(rich, body:)
    Waha::RichPayload.build(rich.deep_stringify_keys, body: body, locale: 'pt_BR')
  end

  describe RichMessages::Types::Event do
    def error(rich, body: 'Vistoria')
      described_class.new(rich.deep_stringify_keys).error_for(body)
    end

    it 'accepts a future event with offset and writes the text version in the offset that came' do
      type = described_class.new(event_rich.deep_stringify_keys)

      expect(type.error_for('Vistoria')).to be_nil
      expect(type.fallback_text('Vistoria'))
        .to eq("🕐 #{start_at.strftime('%d/%m/%Y')} 14:00–15:00\n📍 Av. Paulista, 1000\nVistoria do carro")
      expect(type.whatsapp_cloud_payload('Vistoria')[:text][:body]).to start_with("📅 Vistoria\n🕐 ")
    end

    it 'refuses a past start, a start without offset, an end before the start, and bad texts' do
      expect(error(event_rich.merge(start_at: 1.day.ago.iso8601))).to eq(described_class::START_INVALID)
      expect(error(event_rich.merge(start_at: start_at.strftime('%Y-%m-%dT%H:%M:%S')))).to eq(described_class::START_INVALID)
      expect(error(event_rich.merge(end_at: (start_at - 1.hour).iso8601))).to eq(described_class::END_INVALID)
      expect(error(event_rich, body: '')).to eq(described_class::BODY_INVALID)
      expect(error(event_rich.merge(location_name: "a\nb"))).to eq(described_class::LOCATION_INVALID)
      expect(error(event_rich.merge(description: 'x' * 3000))).to eq(described_class::DESCRIPTION_INVALID)
    end
  end

  describe Waha::RichPayload do
    let(:link) { { type: 'link_button', label: 'Ver proposta', url: 'https://exemplo.com.br/p', header: 'Proposta', footer: 'Válida hoje' } }

    it 'sends the link button as a custom preview card only with an https image' do
      native = payload(link.merge(image_url: 'https://cdn.exemplo.com.br/capa.jpg'), body: 'Segue a proposta')
      allow(engine_client).to receive(:send_link_custom_preview).and_return({ 'id' => 'true_5511@c.us_3EB0LINK' })

      native.deliver(engine_client, session: 's1', chat_id: '5511@c.us', id: 'ignored')

      expect(native.pre_generated_id?).to be(false)
      expect(engine_client).to have_received(:send_link_custom_preview).with(
        session: 's1', chat_id: '5511@c.us', text: "Segue a proposta\n\nhttps://exemplo.com.br/p",
        preview: { url: 'https://exemplo.com.br/p', title: 'Proposta', description: 'Válida hoje',
                   image: { url: 'https://cdn.exemplo.com.br/capa.jpg', mimetype: 'image/jpeg' } }
      )
      expect(native.request['kind']).to eq('sendLinkCustomPreview')
      expect(payload(link, body: 'Segue')).to be_nil
      expect(payload(link.merge(image_url: 'http://inseguro.com/a.jpg'), body: 'Segue')).to be_nil
    end

    it 'sends the event with epoch times and no cancel' do
      native = payload(event_rich, body: 'Vistoria')

      expect(native.request).to eq(
        'kind' => 'sendEvent',
        'payload' => { 'event' => { 'name' => 'Vistoria', 'description' => 'Vistoria do carro', 'startTime' => start_at.to_i,
                                    'endTime' => (start_at + 1.hour).to_i, 'location' => { 'name' => 'Av. Paulista, 1000' },
                                    'extraGuestsAllowed' => false } }
      )
      expect(payload(event_rich.merge(start_at: 1.day.ago.iso8601), body: 'Vistoria')).to be_nil
    end
  end

  describe Waha::EngineCapabilities do
    it 'counts event only when the connector returns the reply' do
      base = { 'rich_native' => %w[options link_button event], 'list_reply' => true }

      expect(described_class.declared({ 'autonomia' => base })).to eq(%w[options link_button])
      expect(described_class.declared({ 'autonomia' => base.merge('event_response' => true) })).to eq(%w[options link_button event])
    end
  end

  describe 'the event type gate' do
    let(:account) { create(:account) }
    let(:inbox) { create(:channel_api, account: account).inbox }
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }
    let(:message) do
      Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Vistoria',
                  content_attributes: { 'rich_message' => event_rich.deep_stringify_keys })
    end

    it 'is an unknown type without the flag, as in main' do
      expect(RichMessages.format_error(message)).to eq(RichMessages::UNKNOWN_TYPE)

      account.enable_features!(Waha::RichNative::FLAG)
      expect(RichMessages.format_error(message)).to be_nil
    end
  end

  describe WhatsappHybrid::RichNative::EventResponseJob do
    include_context 'with a hybrid inbox for rich native'

    def native_event
      flag_on!
      allow(client).to receive(:send_event).and_return({ 'id' => 'true_5511937016094@c.us_3EB0EVT' })
      message = outgoing(event_rich, content: 'Vistoria')
      send_by_web(message)
      message.reload
    end

    def reply(answer, response_id: 'R1')
      described_class.perform_now(connection.id, { 'event_id' => 'true_5511937016094@c.us_3EB0EVT', 'response' => answer,
                                                   'extra_guests' => 0, 'response_id' => response_id, 'from_me' => false })
    end

    it 'aggregates one reply per person on our native event, once per reply id, as a hidden activity' do
      event = native_event
      expect(event.content_attributes['rich_message_sent_as']).to eq('native')

      reply('going')
      reply('going')
      reply('not_going', response_id: 'R2')

      expect(event.reload.content_attributes['event_responses'].sole).to include('sender_type' => 'Contact', 'response' => 'not_going')
      activities = conversation.messages.activity
      expect(activities.pluck(:source_id)).to eq(%w[waha-event-response-R1 waha-event-response-R2])
      expect(activities.first.content_attributes).to include('c2y_hidden' => true, 'event_response_applied_to' => event.id)
      expect(conversation.messages.incoming).to be_empty
    end
  end
end
