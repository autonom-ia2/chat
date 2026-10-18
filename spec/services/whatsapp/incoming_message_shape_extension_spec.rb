require 'rails_helper'

describe Whatsapp::IncomingMessageShapeExtension do
  let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:flow_response_json) { { destino: 'Sao Paulo' }.to_json }
  let(:valid_message) do
    {
      from: '2423423243',
      id: 'wamid.shape-guard',
      timestamp: '1778579582',
      type: 'text',
      text: { body: 'Olá' },
      referral: { source_id: '52558118838064', source_type: 'ad', headline: 'Anúncio' }
    }
  end

  def params_with(message)
    {
      phone_number: whatsapp_channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: { contacts: [{ profile: { name: 'Cliente' }, wa_id: '2423423243' }], messages: [message] } }] }]
    }.with_indifferent_access
  end

  def receive(message)
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params_with(message)).perform
    inbox.messages.last
  end

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  it 'is prepended to the incoming message base service' do
    expect(Whatsapp::IncomingMessageBaseService.ancestors).to include(described_class)
  end

  context 'with a well-formed payload' do
    it 'keeps content and referral as before' do
      message = receive(valid_message)

      expect(message.content).to eq('Olá')
      expect(message.content_attributes['referral']).to include('source_id' => '52558118838064', 'headline' => 'Anúncio')
    end

    it 'keeps the flow response as before' do
      message = receive(valid_message.except(:text, :referral).merge(
                          type: 'interactive',
                          interactive: { type: 'nfm_reply', nfm_reply: { name: 'flow', body: 'Sent', response_json: flow_response_json } }
                        ))

      expect(message.content).to eq(I18n.t('conversations.messages.whatsapp.flow_response'))
      expect(message.content_attributes['whatsapp_flow_response']).to eq(
        'name' => 'flow', 'body' => 'Sent', 'response_json' => { 'destino' => 'Sao Paulo' }
      )
    end

    it 'hands the payload to the core unchanged' do
      service = Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params_with(valid_message))
      payload = valid_message.merge(interactive: { type: 'button_reply', button_reply: { id: '1', title: 'Sim' } }).with_indifferent_access

      expect(service.send(:well_formed_message, payload)).to eq(payload)
    end
  end

  context 'with a field sent as text instead of an object' do
    it 'receives text as a string' do
      message = nil
      expect { message = receive(valid_message.merge(text: 'Olá')) }.not_to raise_error

      expect(message.source_id).to eq('wamid.shape-guard')
      expect(message.content).to be_nil
      expect(message.content_attributes['referral']).to include('source_id' => '52558118838064')
    end

    it 'receives referral as a string' do
      message = nil
      expect { message = receive(valid_message.merge(referral: 'ad')) }.not_to raise_error

      expect(message.content).to eq('Olá')
      expect(message.content_attributes).not_to have_key('referral')
    end

    it 'receives button and name as strings' do
      message = nil
      payload = valid_message.except(:text).merge(type: 'button', button: 'Sim', name: 'Cliente')
      expect { message = receive(payload) }.not_to raise_error

      expect(message.source_id).to eq('wamid.shape-guard')
      expect(message.content).to be_nil
    end

    it 'receives interactive as a string' do
      message = nil
      expect { message = receive(valid_message.except(:text).merge(type: 'interactive', interactive: 'nfm_reply')) }.not_to raise_error

      expect(message.source_id).to eq('wamid.shape-guard')
      expect(message.content_attributes).not_to have_key('whatsapp_flow_response')
    end

    it 'receives nfm_reply as a string' do
      message = nil
      payload = valid_message.merge(type: 'interactive', interactive: { type: 'nfm_reply', nfm_reply: flow_response_json })
      expect { message = receive(payload) }.not_to raise_error

      expect(message.content).to eq('Olá')
      expect(message.content_attributes).not_to have_key('whatsapp_flow_response')
    end

    it 'receives button_reply and list_reply as strings' do
      message = nil
      payload = valid_message.except(:text).merge(type: 'interactive',
                                                  interactive: { type: 'button_reply', button_reply: 'Sim', list_reply: 'Opção' })
      expect { message = receive(payload) }.not_to raise_error

      expect(message.source_id).to eq('wamid.shape-guard')
      expect(message.content).to be_nil
    end
  end
end
