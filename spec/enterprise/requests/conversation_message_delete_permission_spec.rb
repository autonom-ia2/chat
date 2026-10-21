require 'rails_helper'

# Funções personalizadas, lote 7 (#1893): apagar mensagem é a chave conversation_message_delete. Quem tem cargo só apaga
# com ela, e só nas conversas que já opera. Administrador e agente sem cargo seguem como antes.
RSpec.describe 'Apagar mensagem e a chave conversation_message_delete', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Original') }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def apagar(user = agent)
    delete path, headers: user.create_new_auth_token, as: :json
  end

  it 'cargo que atende sem a chave não apaga, e a mensagem fica intacta' do
    give_role(%w[conversation_participating_manage])
    apagar

    expect(response).to have_http_status(:unauthorized)
    expect(message.reload.content).to eq('Original')
    expect(message.deleted).to be_falsey
  end

  it 'cargo com a chave apaga a mensagem da conversa que atende' do
    give_role(%w[conversation_participating_manage conversation_message_delete])
    apagar

    expect(response).to have_http_status(:ok)
    expect(message.reload.deleted).to be true
  end

  it 'a chave não abre conversa que o cargo não opera' do
    conversation.update!(assignee: create(:user, account: account, role: :agent))
    give_role(%w[conversation_participating_manage conversation_message_delete])
    apagar

    expect(response).to have_http_status(:unauthorized)
    expect(message.reload.deleted).to be_falsey
  end

  it 'quem só lê não apaga, mesmo com a chave' do
    give_role(%w[conversation_view conversation_message_delete])
    apagar

    expect(response).to have_http_status(:unauthorized)
    expect(message.reload.deleted).to be_falsey
  end

  it 'agente sem cargo segue apagando' do
    apagar

    expect(response).to have_http_status(:ok)
    expect(message.reload.deleted).to be true
  end

  it 'administrador segue apagando' do
    admin = create(:user, account: account, role: :administrator)
    apagar(admin)

    expect(response).to have_http_status(:ok)
    expect(message.reload.deleted).to be true
  end
end
