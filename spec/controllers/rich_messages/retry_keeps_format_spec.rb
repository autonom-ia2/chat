require 'rails_helper'

# chat#1473 (P1a): reenviar uma mensagem com `rich_message` que falhou não pode apagar o formato dela.
describe RichMessages::RetryKeepsFormat, type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:rich_message) { { 'type' => 'link_button', 'label' => 'Abrir', 'url' => 'https://exemplo.com.br/x' } }

  def failed_message(content_attributes)
    create(:message, account: account, message_type: :outgoing, status: :failed,
                     content_attributes: content_attributes.merge(external_error: 'erro'))
  end

  def retry_message(message)
    create(:inbox_member, inbox: message.conversation.inbox, user: agent)
    post "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry",
         headers: agent.create_new_auth_token, as: :json
    message.reload
  end

  it 'keeps rich_message and the keys it does not know, clears the error and enqueues the send again' do
    message = failed_message(rich_message: rich_message, autonomia_chunk_token: 'tok-1')

    expect { retry_message(message) }.to have_enqueued_job(SendReplyJob).with(message.id)

    expect(response).to have_http_status(:success)
    expect(message.status).to eq('sent')
    expect(message.content_attributes).to eq('rich_message' => rich_message, 'autonomia_chunk_token' => 'tok-1')
  end

  it 'drops the marks of the previous transport, so the bubble is not shown as sent by WhatsApp API' do
    message = failed_message(rich_message: rich_message, whatsapp_transport: 'web', whatsapp_transport_origin: 'human',
                             whatsapp_transport_fallback: true, whatsapp_transport_outcome: 'sent', whatsapp_web_id: '3EB0',
                             crm_follow_up_id: 9)

    expect(retry_message(message).content_attributes).to eq('rich_message' => rich_message, 'crm_follow_up_id' => 9)
  end

  it 'drops the sent-as-text marks of the previous attempt (chat#1555)' do
    message = failed_message(rich_message: rich_message, rich_message_sent_as: 'text', rich_message_sent_text: 'Abrir: x')

    expect(retry_message(message).content_attributes).to eq('rich_message' => rich_message)
  end

  [{}, '', [], false].each do |value|
    it "keeps a rich_message that is #{value.inspect}, so the retry fails again instead of going out as plain text" do
      message = failed_message(rich_message: value)

      expect(retry_message(message).content_attributes).to eq('rich_message' => value)
    end
  end

  it 'still resets content_attributes of a message without rich_message' do
    message = failed_message(in_reply_to: 1)

    expect(retry_message(message).content_attributes).to eq({})
  end
end
