require 'rails_helper'

# chat#1473 (P3): a resposta do cliente a um botão ou a uma lista guarda o `id` da opção, além do título.
describe RichMessages::SelectedOption do
  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:offered) do
    contact = create(:contact, account: inbox.account, phone_number: '+2423423243')
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '2423423243')
    conversation = create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account)
    create(:message, message_type: :outgoing, conversation: conversation, inbox: inbox, account: inbox.account,
                     content: 'Como você prefere continuar?', source_id: 'wamid.opcoes-enviadas')
  end

  # O webhook `messages` da Meta como chega, com a resposta apontando a mensagem das opções em `context.id`.
  def webhook(message)
    {
      phone_number: channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Camila' }, wa_id: '2423423243' }],
        messages: [{ context: { from: channel.phone_number, id: offered.source_id }, from: '2423423243',
                     id: 'wamid.resposta', timestamp: '1760371200' }.merge(message)]
      } }] }]
    }.with_indifferent_access
  end

  def receive(message)
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: webhook(message)).perform
    inbox.messages.find_by!(source_id: 'wamid.resposta')
  end

  it 'keeps the id and the title of a tapped reply button, linked to the message that offered it' do
    reply = receive(type: 'interactive', interactive: { type: 'button_reply', button_reply: { id: 'agendar', title: 'Agendar visita' } })

    expect(reply.content).to eq('Agendar visita')
    expect(reply.content_attributes['selected_option']).to eq('id' => 'agendar', 'title' => 'Agendar visita')
    expect(reply.content_attributes['in_reply_to']).to eq(offered.id)
    expect(reply.webhook_data[:content_attributes]['selected_option']).to eq('id' => 'agendar', 'title' => 'Agendar visita')
  end

  it 'keeps the id and the title of a tapped list row' do
    reply = receive(type: 'interactive', interactive: { type: 'list_reply',
                                                        list_reply: { id: 'remarcar', title: 'Remarcar horário',
                                                                      description: 'Trocar o dia ou a hora' } })

    expect(reply.content).to eq('Remarcar horário')
    expect(reply.content_attributes['selected_option']).to eq('id' => 'remarcar', 'title' => 'Remarcar horário')
  end

  it 'keeps the payload of a tapped quick reply button from a template as the id' do
    reply = receive(type: 'button', button: { payload: 'confirmar-visita', text: 'Confirmar' })

    expect(reply.content).to eq('Confirmar')
    expect(reply.content_attributes['selected_option']).to eq('id' => 'confirmar-visita', 'title' => 'Confirmar')
  end

  it 'leaves a plain text answer as it was' do
    reply = receive(type: 'text', text: { body: 'Quero agendar' })

    expect(reply.content).to eq('Quero agendar')
    expect(reply.content_attributes).not_to have_key('selected_option')
    expect(reply.content_attributes['in_reply_to']).to eq(offered.id)
  end

  context 'with a 360dialog inbox' do
    let(:dialog_channel) { create(:channel_whatsapp, sync_templates: false) }

    before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

    # O webhook do 360dialog chega sem o envelope `entry`/`changes` da Meta, com o mesmo item `messages[]`.
    it 'keeps the id and the title of a tapped list row' do
      params = {
        contacts: [{ profile: { name: 'Camila' }, wa_id: '2423423243' }],
        messages: [{ from: '2423423243', id: 'wamid.resposta-360', timestamp: '1760371200', type: 'interactive',
                     interactive: { type: 'list_reply', list_reply: { id: 'boleto', title: 'Segunda via do boleto' } } }]
      }.with_indifferent_access

      Whatsapp::IncomingMessageService.new(inbox: dialog_channel.inbox, params: params).perform
      reply = dialog_channel.inbox.messages.find_by!(source_id: 'wamid.resposta-360')

      expect(reply.content).to eq('Segunda via do boleto')
      expect(reply.content_attributes['selected_option']).to eq('id' => 'boleto', 'title' => 'Segunda via do boleto')
    end
  end
end
