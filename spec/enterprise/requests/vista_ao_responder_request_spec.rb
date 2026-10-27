require 'rails_helper'

# #2202 (PR 0) pelo caminho real do envio, Api::V1::Accounts::Conversations::MessagesController#create: só a resposta
# de uma pessoa da conta apaga a bolinha. Fica aqui (enterprise) por causa do token do MCP.
RSpec.describe 'Resposta pela API e a bolinha de não lida (#2202)', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:ana) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:conversa) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open,
                          agent_last_seen_at: 1.day.ago)
  end

  before do
    create(:inbox_member, user: ana, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, sender: contact,
                     created_at: 1.hour.ago)
  end

  def responder(headers, **extra)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
         params: { content: 'Oi, já vi', private: false }.merge(extra), headers: headers, as: :json
  end

  def nao_lidas
    conversa.reload.unread_incoming_messages.count
  end

  it 'token de API de uma pessoa apaga a bolinha', :aggregate_failures do
    responder({ 'api_access_token' => ana.access_token.token })

    expect(response).to have_http_status(:success)
    expect(nao_lidas).to eq(0)
  end

  it 'token de AgentBot não apaga', :aggregate_failures do
    bot = create(:agent_bot, account: account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)

    responder({ 'api_access_token' => bot.access_token.token })

    expect(response).to have_http_status(:success)
    expect(conversa.messages.outgoing.last.sender).to eq(bot)
    expect(nao_lidas).to eq(1)
  end

  it 'token de integração do MCP não apaga', :aggregate_failures do
    admin = create(:user, account: account, role: :administrator)
    link = Autonomia::UserLink.create!(identity_user_id: "mcp-#{SecureRandom.hex(3)}", user: admin, email: admin.email)
    token = Mcp::IntegrationToken.create!(account: account, created_by: admin, identity_subject: link.identity_user_id,
                                          name: 'MCP', scopes: Mcp::IntegrationToken::DEFAULT_SCOPES)

    responder({ 'api_access_token' => token.access_token.token, 'Idempotency-Key' => "m-#{SecureRandom.hex(6)}" })

    expect(response).to have_http_status(:success)
    expect(conversa.messages.outgoing.last.sender).to eq(token.account_user.user)
    expect(nao_lidas).to eq(1)
  end

  # #2216/#2240: com o sinal da gaveta, a reabertura e a mensagem vão numa transação só; o "visto" anda no
  # after_create_commit da mensagem, depois do COMMIT dessa transação.
  it 'resposta com o sinal reabrir_ao_escrever reabre e faz o visto avançar depois do commit', :aggregate_failures do
    inbox.update!(lock_to_single_conversation: true)
    conversa.update!(status: :resolved)

    responder(ana.create_new_auth_token, reabrir_ao_escrever: true)

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_open
    expect(conversa.agent_last_seen_at).to be > 1.minute.ago
    expect(nao_lidas).to eq(0)
  end
end
