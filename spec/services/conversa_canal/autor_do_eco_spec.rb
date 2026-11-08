require 'rails_helper'

# #1941: o eco do celular (Cloud com coexistência e caixa híbrida) grava quem estava atribuído quando chegou.
describe ConversaCanal::AutorDoEco do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { channel.account }
  let(:inbox) { channel.inbox }
  let(:joao) { create(:user, account: account, name: 'João') }
  let(:jose) { create(:user, account: account, name: 'José') }
  let(:cliente) { '5511900000001' }

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  def recebida(id)
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Camila Duarte' }, wa_id: cliente }],
        messages: [{ from: cliente, id: id, timestamp: '1760371920', type: 'text', text: { body: 'oi' } }]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
    Message.find_by!(source_id: id)
  end

  def eco(id)
    params = {
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'smb_message_echoes', value: {
        message_echoes: [{ from: channel.phone_number.delete('+'), to: cliente, id: id,
                           timestamp: '1760371980', type: 'text', text: { body: 'respondi pelo celular' } }]
      } }] }]
    }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params, outgoing_echo: true).perform
    Message.find_by!(source_id: id)
  end

  it 'grava quem estava atribuído quando o eco chegou' do
    conversa = recebida('wamid.in-1').conversation
    conversa.update!(assignee: joao)

    mensagem = eco('wamid.eco-1')

    expect(mensagem).to be_outgoing
    expect(mensagem.conversation).to eq(conversa)
    expect(mensagem.content_attributes).to include('external_echo' => true, 'c2y_phone_author_id' => joao.id)
  end

  it 'grava null quando a conversa não tem atribuição' do
    recebida('wamid.in-2')

    mensagem = eco('wamid.eco-2')

    expect(mensagem.content_attributes).to have_key('c2y_phone_author_id')
    expect(mensagem.content_attributes['c2y_phone_author_id']).to be_nil
  end

  it 'não põe a chave na mensagem que não é eco' do
    mensagem = recebida('wamid.in-3')

    expect(mensagem.content_attributes).not_to have_key('c2y_phone_author_id')
  end

  it 'reatribuir depois não muda as antigas; o eco novo leva o novo nome' do
    conversa = recebida('wamid.in-4').conversation
    conversa.update!(assignee: joao)
    antiga = eco('wamid.eco-4a')

    conversa.update!(assignee: jose)
    nova = eco('wamid.eco-4b')

    expect(antiga.reload.content_attributes['c2y_phone_author_id']).to eq(joao.id)
    expect(nova.content_attributes['c2y_phone_author_id']).to eq(jose.id)
  end
end
