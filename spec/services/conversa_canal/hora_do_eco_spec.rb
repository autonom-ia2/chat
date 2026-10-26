require 'rails_helper'

# #2202: o eco da Cloud (coexistência e Híbrido) guarda a hora em que saiu do celular, do `timestamp` do webhook.
describe ConversaCanal::HoraDoEco do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:cliente) { '5511900000001' }

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  def webhook(campo, chave, mensagem, eco: false)
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: campo, value: {
        'contacts' => [{ profile: { name: 'Cliente' }, wa_id: cliente }], chave.to_s => [mensagem]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params, outgoing_echo: eco).perform
    Message.find_by!(source_id: mensagem[:id])
  end

  it 'o eco guarda a hora do envio' do
    webhook('messages', :messages, { from: cliente, id: 'wamid.in-1', timestamp: '1760371920', type: 'text', text: { body: 'oi' } })
    eco = webhook('smb_message_echoes', :message_echoes,
                  { from: channel.phone_number.delete('+'), to: cliente, id: 'wamid.eco-1', timestamp: '1760371980',
                    type: 'text', text: { body: 'respondi pelo celular' } }, eco: true)

    expect(eco.content_attributes['external_created_at']).to eq(1_760_371_980)
  end

  it 'a mensagem recebida não ganha a chave' do
    recebida = webhook('messages', :messages,
                       { from: cliente, id: 'wamid.in-2', timestamp: '1760371920', type: 'text', text: { body: 'oi' } })

    expect(recebida.content_attributes).not_to have_key('external_created_at')
  end
end
