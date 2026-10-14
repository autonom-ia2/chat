require 'rails_helper'

# chat#1505: contactable_inboxes leva, dentro de cada caixa, a conversa em que a mensagem da gaveta entraria.
RSpec.describe 'GET contactable_inboxes conversation_to_continue', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:email_inbox) { create(:inbox, account: account, channel: create(:channel_email, account: account)) }
  let(:contact) { create(:contact, account: account, email: 'ana@example.com') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: email_inbox, source_id: contact.email) }

  def conversation_with(status, target_contact_inbox: contact_inbox)
    create(:conversation, account: account, inbox: email_inbox, contact: contact, contact_inbox: target_contact_inbox,
                          status: status)
  end

  def entry
    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body['payload'].find { |item| item['inbox']['id'] == email_inbox.id }
  end

  it 'sends the conversation of the contact inbox the drawer will use' do
    open_conversation = conversation_with(:open)
    other_identity = create(:contact_inbox, contact: contact, inbox: email_inbox, source_id: 'antigo@example.com')
    conversation_with(:open, target_contact_inbox: other_identity)

    expect(entry['source_id']).to eq(contact.email)
    expect(entry['inbox']['conversation_to_continue']).to eq(
      'id' => open_conversation.id, 'display_id' => open_conversation.display_id, 'status' => 'open',
      'last_activity_at' => open_conversation.last_activity_at.to_i, 'locked' => false, 'visible' => true
    )
  end

  it 'sends null when there is nothing to continue' do
    conversation_with(:resolved)

    body = entry
    expect(body['inbox']).to have_key('conversation_to_continue')
    expect(body['inbox']['conversation_to_continue']).to be_nil
  end
end
