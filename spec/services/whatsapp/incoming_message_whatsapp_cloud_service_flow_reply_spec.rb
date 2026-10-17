require 'rails_helper'

# #1702: a resposta do formulário (nfm_reply) precisa chegar ligada ao formulário que a originou (citação no
# painel) e com tudo o que o Cloud manda: response_json completo (com o flow_token dentro), name e body.
describe Whatsapp::IncomingMessageWhatsappCloudService do
  before { inbox.account.enable_features!('conversa_cara_do_canal') }

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  let!(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { whatsapp_channel.inbox }
  let(:sender_number) { '2423423243' }
  let(:contact) { create(:contact, account: inbox.account, phone_number: "+#{sender_number}") }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: sender_number) }
  let!(:conversation) { create(:conversation, account: inbox.account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let!(:flow_message) do
    create(:message, account: inbox.account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     source_id: 'wamid.formulario-enviado', content: 'Preencha seus dados.',
                     content_attributes: { rich_message: { type: 'flow', flow_id: '123', cta: 'Começar', token: 'tok-1',
                                                           screen: 'INICIO', name: 'Cotação' } })
  end
  let(:response_json) { { flow_token: 'tok-1', screen_0_Nome_0: 'Ana' }.to_json }
  let(:params) do
    {
      phone_number: whatsapp_channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          value: {
            contacts: [{ profile: { name: 'Ana' }, wa_id: sender_number }],
            messages: [{
              context: { from: whatsapp_channel.phone_number, id: 'wamid.formulario-enviado' },
              from: sender_number, id: 'wamid.resposta-do-formulario', timestamp: '1778579582', type: 'interactive',
              interactive: { type: 'nfm_reply', nfm_reply: { name: 'flow', body: 'Sent', response_json: response_json } }
            }]
          }
        }]
      }]
    }.with_indifferent_access
  end

  it 'liga a resposta ao formulário enviado e grava response_json, flow_token, name e body' do
    described_class.new(inbox: inbox, params: params).perform

    reply = inbox.messages.find_by(source_id: 'wamid.resposta-do-formulario')
    expect(reply.conversation_id).to eq(conversation.id)
    expect(reply.content_attributes['in_reply_to']).to eq(flow_message.id)
    expect(reply.content_attributes['in_reply_to_external_id']).to eq('wamid.formulario-enviado')
    expect(reply.content_attributes['whatsapp_flow_response']).to eq(
      'name' => 'flow', 'body' => 'Sent', 'response_json' => { 'flow_token' => 'tok-1', 'screen_0_Nome_0' => 'Ana' }
    )
    expect(reply.content_attributes['flow_response']).to include('type' => 'nfm_reply', 'flow_token' => 'tok-1')
  end

  it 'com a chave desligada, o flow_token de dentro do response_json não é lido (contrato de sempre do n8n)' do
    inbox.account.disable_features!('conversa_cara_do_canal')

    described_class.new(inbox: inbox, params: params).perform

    reply = inbox.messages.find_by(source_id: 'wamid.resposta-do-formulario')
    expect(reply.content_attributes['flow_response']).not_to have_key('flow_token')
  end
end
