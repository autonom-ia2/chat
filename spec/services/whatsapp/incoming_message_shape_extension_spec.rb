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

  # RichMessages::SelectedOption lê interactive e button sem checar o tipo: só é seguro porque roda por dentro desta extensão.
  it 'wraps the fork extensions that read the same fields' do
    ancestors = Whatsapp::IncomingMessageBaseService.ancestors

    expect(ancestors.index(described_class)).to be < ancestors.index(RichMessages::SelectedOption)
    expect(ancestors.index(described_class)).to be < ancestors.index(ConversaCanal::RecebimentoDoWhatsapp)
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

    it 'keeps the selected option as before' do
      message = receive(valid_message.except(:text).merge(type: 'interactive',
                                                          interactive: { type: 'button_reply', button_reply: { id: 'sim', title: 'Sim' } }))

      expect(message.content).to eq('Sim')
      expect(message.content_attributes['selected_option']).to eq('id' => 'sim', 'title' => 'Sim')
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
      expect(message.conversation.additional_attributes).not_to have_key('campaign')
    end

    it 'receives button as a string' do
      message = nil
      expect { message = receive(valid_message.except(:text).merge(type: 'button', button: 'Sim')) }.not_to raise_error

      expect(message.source_id).to eq('wamid.shape-guard')
      expect(message.content).to be_nil
      expect(message.content_attributes).not_to have_key('selected_option')
    end

    it 'receives name as a string' do
      message = nil
      expect { message = receive(valid_message.except(:text).merge(name: 'Cliente')) }.not_to raise_error

      expect(message.source_id).to eq('wamid.shape-guard')
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

    %i[button_reply list_reply].each do |reply|
      it "receives #{reply} as a string" do
        message = nil
        payload = valid_message.except(:text).merge(type: 'interactive', interactive: { 'type' => reply.to_s, reply.to_s => 'Sim' })
        expect { message = receive(payload) }.not_to raise_error

        expect(message.source_id).to eq('wamid.shape-guard')
        expect(message.content).to be_nil
        expect(message.content_attributes).not_to have_key('selected_option')
      end
    end

    it 'does not change the message it reads' do
      service = Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params_with(valid_message))
      payload = valid_message.merge(text: 'Olá', interactive: { type: 'nfm_reply', nfm_reply: 'x' }).with_indifferent_access
      original = payload.deep_dup

      expect(service.message_content(payload)).to be_nil
      expect(payload).to eq(original)
    end
  end
end
