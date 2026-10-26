require 'rails_helper'

# #2216 com #1800: quem só lê (conversation_view sem o trio) continua sem começar conversa, e a conversa resolvida que a
# criação acharia continua resolvida.
RSpec.describe 'Começar conversa com quem só lê (#2216)', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:leitora) do
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: %w[conversation_view])
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    inbox.add_members([user.id])
    user
  end

  it 'recusa e não reabre a conversa resolvida' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved)

    expect do
      post "/api/v1/accounts/#{account.id}/conversations",
           params: { source_id: contact_inbox.source_id, inbox_id: inbox.id, contact_id: contact.id, message: { content: 'oi' } },
           headers: leitora.create_new_auth_token, as: :json
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:unauthorized)
    expect(conversa.reload).to be_resolved
  end

  it 'recusa a mensagem com o sinal da gaveta e não reabre a conversa resolvida' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved)

    expect do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
           params: { content: 'oi', private: false, reabrir_ao_escrever: true },
           headers: leitora.create_new_auth_token, as: :json
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:unauthorized)
    expect(conversa.reload).to be_resolved
  end
end
