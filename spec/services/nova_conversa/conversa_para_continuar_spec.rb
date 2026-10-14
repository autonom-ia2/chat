require 'rails_helper'

# chat#1505: a gaveta "Nova conversa" continua a conversa que a regra da caixa escolheria se o cliente escrevesse.
describe NovaConversa::ConversaParaContinuar, type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: false) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  def conversation_with(status, target_inbox: inbox, target_contact: contact)
    ci = target_inbox == inbox && target_contact == contact ? contact_inbox : create(:contact_inbox, contact: target_contact, inbox: target_inbox)
    create(:conversation, account: account, inbox: target_inbox, contact: target_contact, contact_inbox: ci, status: status)
  end

  def result
    described_class.new(inbox: inbox, contact: contact).conversation
  end

  context 'when the inbox reopens the same conversation' do
    before { inbox.update!(lock_to_single_conversation: true) }

    it 'returns the latest conversation even when it is resolved' do
      conversation_with(:open)
      resolved = conversation_with(:resolved)

      expect(result).to eq(resolved)
    end

    it 'marks the payload as locked' do
      resolved = conversation_with(:resolved)

      expect(described_class.new(inbox: inbox, contact: contact).payload).to eq(
        id: resolved.id, display_id: resolved.display_id, status: 'resolved',
        last_activity_at: resolved.last_activity_at.to_i, locked: true
      )
    end
  end

  context 'when the inbox creates new conversations' do
    it 'ignores resolved conversations' do
      conversation_with(:resolved)

      expect(result).to be_nil
      expect(described_class.new(inbox: inbox, contact: contact).payload).to be_nil
    end

    it 'returns the most recent conversation that is not resolved' do
      conversation_with(:pending)
      latest_open = conversation_with(:open)
      conversation_with(:resolved)

      expect(result).to eq(latest_open)
    end

    it 'counts snoozed conversations as open' do
      snoozed = conversation_with(:snoozed)

      expect(result).to eq(snoozed)
    end

    it 'does not count conversations from another inbox or another contact' do
      conversation_with(:open, target_inbox: create(:inbox, account: account))
      conversation_with(:open, target_contact: create(:contact, account: account))

      expect(result).to be_nil
    end
  end

  describe 'GET contactable_inboxes' do
    let(:email_inbox) { create(:inbox, account: account, channel: create(:channel_email, account: account)) }
    let(:contact) { create(:contact, account: account, email: 'ana@example.com') }
    let(:inbox) { email_inbox }

    def entry
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/contactable_inboxes",
          headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      response.parsed_body['payload'].find { |item| item['inbox']['id'] == email_inbox.id }
    end

    it 'sends the conversation to continue inside the inbox' do
      open_conversation = conversation_with(:open)

      expect(entry['inbox']['conversation_to_continue']).to eq(
        'id' => open_conversation.id, 'display_id' => open_conversation.display_id, 'status' => 'open',
        'last_activity_at' => open_conversation.last_activity_at.to_i, 'locked' => false
      )
    end

    it 'sends null when there is nothing to continue' do
      conversation_with(:resolved)

      body = entry
      expect(body['inbox']).to have_key('conversation_to_continue')
      expect(body['inbox']['conversation_to_continue']).to be_nil
    end
  end
end
