require 'rails_helper'

# chat#1473 (P1a): reenviar uma mensagem de botão que falhou não pode apagar o formato dela.
describe RichMessages::RetryKeepsFormat, type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:rich_message) { { 'type' => 'link_button', 'label' => 'Abrir', 'url' => 'https://exemplo.com.br/x' } }

  def retry_message(message)
    create(:inbox_member, inbox: message.conversation.inbox, user: agent)
    post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
         headers: agent.create_new_auth_token, as: :json
    message.reload
  end

  it 'keeps rich_message and the keys it does not know, clears the error and enqueues the send again' do
    message = create(:message, account: account, message_type: :outgoing, status: :failed,
                               content_attributes: { rich_message: rich_message, autonomia_chunk_token: 'tok-1', external_error: 'erro' })

    expect { retry_message(message) }.to have_enqueued_job(SendReplyJob).with(message.id)

    expect(response).to have_http_status(:success)
    expect(message.status).to eq('sent')
    expect(message.content_attributes['rich_message']).to eq(rich_message)
    expect(message.content_attributes['autonomia_chunk_token']).to eq('tok-1')
    expect(message.content_attributes['external_error']).to be_nil
  end

  it 'still resets content_attributes of a message without rich_message' do
    message = create(:message, account: account, message_type: :outgoing, status: :failed,
                               content_attributes: { external_error: 'erro', in_reply_to: 1 })

    expect(retry_message(message).content_attributes).to eq({})
  end
end
