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

  it 'drops them also when content_attributes comes as JSON text' do
    message = create_message(content: 'Oi', content_attributes: { waha_native: { kind: 'sendList' }, outro: 'fica' }.to_json)

    expect(message.content_attributes).to eq('outro' => 'fica')
  end

  it 'keeps waha_list_reply on an incoming message (the connector) and converts it' do
    message = create_message(content: 'Manhã', message_type: 'incoming',
                             content_attributes: { waha_list_reply: { row_id: 'manha', title: 'Manhã' }, waha_native: { kind: 'x' } })

    expect(message.content_attributes).to eq('selected_option' => { 'id' => 'manha', 'title' => 'Manhã' })
  end
end
