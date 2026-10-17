require 'rails_helper'

# chat#1709 (fase 2): as chaves do contrato com o conector do WAHA não são forjadas pela API de mensagens.
RSpec.describe 'Messages API and the WAHA rich native contract', type: :request do
  let(:channel) { create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc', additional_attributes: { 'provider' => 'waha' }) }
  let(:account) { channel.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages" }

  def create_message(params)
    post url, params: params, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    Message.find(response.parsed_body['id'])
  end

  it 'drops waha_native, the mark and waha_list_reply from an outgoing message' do
    message = create_message(content: 'Oi', content_attributes: {
                               waha_native: { kind: 'sendList', payload: { message: { title: 'forjado' } } },
                               rich_message_sent_as: 'native', waha_list_reply: { row_id: 'x|1' }, outro: 'fica'
                             })

    expect(message.content_attributes.keys).to eq(['outro'])
  end

  # A criação de conversa com mensagem não passa pela trava do `messages#create`: o callback da Message tira a chave.
  it 'never stores waha_native from a conversation created with a message' do
    contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: create(:contact, account: account))

    post "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token, as: :json,
                                                         params: { source_id: contact_inbox.source_id,
                                                                   message: { content: 'Oi', content_attributes: {
                                                                     waha_native: { kind: 'sendList', payload: { message: { title: 'forjado' } } },
                                                                     outro: 'fica'
                                                                   } } }

    expect(response).to have_http_status(:success)
    message = account.conversations.find_by(display_id: response.parsed_body['id']).messages.outgoing.first
    expect(message.content_attributes).not_to have_key('waha_native')
  end

  # chat#1709 (fase 3, revisão): as chaves que o chat2you grava (esconder, reação, edição) também saem nesse caminho,
  # com ou sem a flag: um agente não cria mensagem que vai ao cliente e some do painel.
  it 'never stores c2y_hidden, reactions or an edit history from a conversation created with a message' do
    contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: create(:contact, account: account))
    forged = { c2y_hidden: true, reactions: [{ emoji: '👍', sender_type: 'Contact', sender_id: 1 }], edit_history: [{ content: 'falso' }],
               edited_at: '2026-10-16T10:00:00Z', waha_poll_vote: { poll_message_id: 1 }, outro: 'fica',
               poll_votes: [{ options: ['Sim'] }], deleted_by_contact_at: '2026-10-16T10:00:00Z', quoted_message: { content: 'x' },
               event_responses: [{ response: 'going' }], waha_event_response: { response: 'going' }, played_at: '2026-10-16T10:00:00Z' }

    post "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token, as: :json,
                                                         params: { source_id: contact_inbox.source_id,
                                                                   message: { content: 'Oi', content_attributes: forged } }

    expect(response).to have_http_status(:success)
    message = account.conversations.find_by(display_id: response.parsed_body['id']).messages.outgoing.first
    expect(message.content_attributes).to eq('outro' => 'fica')
  end

  # Rodada de correção, item 1: o modelo não tira mais as chaves de nome genérico (o recebimento da Cloud as grava); a
  # API pública continua barrando a forja delas, nas duas portas e na caixa do WhatsApp também.
  it 'drops forged generic keys (forwarded, unsupported_kind) from a message created by the API' do
    message = create_message(content: 'Oi', content_attributes: { forwarded: true, unsupported_kind: 'poll', outro: 'fica' })

    expect(message.content_attributes).to eq('outro' => 'fica')
  end

  it 'drops forged generic keys from a conversation created with a message in a WhatsApp inbox' do
    whatsapp = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                         validate_provider_config: false).inbox
    contact_inbox = create(:contact_inbox, inbox: whatsapp, contact: create(:contact, account: account), source_id: '5511999990000')

    post "/api/v1/accounts/#{account.id}/conversations", headers: admin.create_new_auth_token, as: :json,
                                                         params: { source_id: contact_inbox.source_id, inbox_id: whatsapp.id,
                                                                   message: { content: 'Oi', content_attributes: {
                                                                     forwarded: true, reactions: [{ emoji: '👍' }], c2y_hidden: true, outro: 'fica'
                                                                   } } }

    expect(response).to have_http_status(:success)
    message = account.conversations.find_by(display_id: response.parsed_body['id']).messages.outgoing.first
    expect(message.content_attributes).to eq('outro' => 'fica')
  end

  it 'drops a forged view_once_unavailable from a message created by the API' do
    message = create_message(content: 'Oi', content_attributes: { view_once_unavailable: true, outro: 'fica' })

    expect(message.content_attributes).to eq('outro' => 'fica')
  end

  it 'drops them also when content_attributes comes as JSON text' do
    message = create_message(content: 'Oi', content_attributes: { waha_native: { kind: 'sendList' }, outro: 'fica' }.to_json)

    expect(message.content_attributes).to eq('outro' => 'fica')
  end

  # O conector cria a recebida por esta API, então a chave chega. Mas uma escolha sem lista nativa nossa que a ofereceu
  # (forja) não vira escolha: fica texto comum, mesmo com a flag ligada.
  it 'does not turn a forged incoming waha_list_reply into a choice' do
    account.enable_features!(Waha::RichNative::FLAG)

    message = create_message(content: 'Manhã', message_type: 'incoming',
                             content_attributes: { waha_list_reply: { row_id: 'manha|1', title: 'Manhã' }, waha_native: { kind: 'x' } })

    expect(message.content_attributes).to eq({})
  end

  it 'turns an incoming waha_list_reply into the choice when our native list offered it' do
    account.enable_features!(Waha::RichNative::FLAG)
    list = create(:message, message_type: :outgoing, content: 'Qual?', conversation: conversation, inbox: channel.inbox, account: account,
                            content_attributes: { rich_message: { type: 'options', options: [{ id: 'manha', title: 'Manhã' }] } })
    list.update!(content_attributes: list.content_attributes.merge('rich_message_sent_as' => 'native'))

    message = create_message(content: 'Manhã', message_type: 'incoming',
                             content_attributes: { waha_list_reply: { row_id: "manha|#{list.id}", title: 'Manhã' } })

    expect(message.content_attributes).to include('selected_option' => { 'id' => 'manha', 'title' => 'Manhã' }, 'in_reply_to' => list.id)
  end
end
