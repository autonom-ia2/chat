require 'rails_helper'

# #2216 com #1800, funções personalizadas e MCP: a mensagem da gaveta com o sinal de reabrir não passa da permissão de
# quem escreve. Quem só lê e quem só atende as conversas em que participa são recusados na conversa de outra pessoa; o
# token do MCP manda mensagem, mas não reabre (ele também não troca status).
RSpec.describe 'Mensagem da gaveta: quem pode reabrir (#2216)', type: :request do
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

  describe 'função só com conversation_participating_manage' do
    let(:dona) { create(:user, account: account, role: :agent) }
    let(:participante) do
      user = create(:user, account: account, role: :agent)
      role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}",
                                permissions: %w[conversation_participating_manage])
      AccountUser.find_by(account: account, user: user).update!(custom_role: role)
      inbox.add_members([user.id, dona.id])
      user
    end
    let!(:conversa) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                            status: :resolved, assignee: dona)
    end

    it 'recebe 401 ao mandar mensagem com o sinal na conversa de outra pessoa' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
           params: { content: 'oi', private: false, reabrir_ao_escrever: true },
           headers: participante.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(conversa.reload).to be_resolved
    end
  end

  it 'o token do MCP manda a mensagem, mas não reabre (ele também não troca status)' do
    admin = create(:user, account: account, role: :administrator)
    link = Autonomia::UserLink.create!(identity_user_id: "mcp-#{SecureRandom.hex(3)}", user: admin, email: admin.email)
    token = Mcp::IntegrationToken.create!(account: account, created_by: admin, identity_subject: link.identity_user_id,
                                          name: 'MCP', scopes: Mcp::IntegrationToken::DEFAULT_SCOPES)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved)
    headers = { 'api_access_token' => token.access_token.token, 'Idempotency-Key' => "t-#{SecureRandom.hex(6)}" }

    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/toggle_status",
         params: { status: 'open' }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
         params: { content: 'oi', reabrir_ao_escrever: true },
         headers: headers.merge('Idempotency-Key' => "m-#{SecureRandom.hex(6)}"), as: :json

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end
end
