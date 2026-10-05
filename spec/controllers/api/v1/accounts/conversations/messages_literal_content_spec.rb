require 'rails_helper'

# chat#1021: the literal mark is set only by fork code. A client sending it in content_attributes
# gets the normal Liquid pass.
RSpec.describe 'Conversation Messages API literal mark', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'john') }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: contact) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'renders Liquid even when content_attributes carries literal_content' do
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { content: 'hey {{contact.name}}', content_attributes: { literal_content: true } },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    expect(conversation.messages.last.content).to eq('hey John')
  end

  it 'ignores a top-level literal_content param' do
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { content: 'hey {{contact.name}}', literal_content: true },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    expect(conversation.messages.last.content).to eq('hey John')
  end
end
