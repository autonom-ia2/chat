require 'rails_helper'

# #2216: começar conversa numa caixa com "Reabrir a mesma conversa" (lock_to_single_conversation) cai na última conversa
# do contato. Resolvida ou adiada, ela reabre quando vem mensagem com o sinal da gaveta (`reabrir_ao_escrever`), sem
# mudar quem cuida (#2067: atendente responde, não assume). Só pessoa com sessão do painel: robô, token de API e
# integração não reabrem. O ConversationBuilder (widget, campanhas, avisos) fica como está.
RSpec.describe 'Começar conversa reabre a resolvida ou adiada (#2216)', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:contact) { create(:contact, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:dona) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:team) { create(:team, account: account) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: dona, inbox: inbox)
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  def comecar(message: { content: 'Oi, tudo bem?' }, sinal: true, headers: agent.create_new_auth_token)
    params = { source_id: contact_inbox.source_id, inbox_id: inbox.id, contact_id: contact.id }
    params[:message] = message if message
    params[:reabrir_ao_escrever] = sinal unless sinal.nil?
    post "/api/v1/accounts/#{account.id}/conversations", headers: headers, params: params, as: :json
  end

  def resolvida_da_dona
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                          status: :resolved, assignee: dona)
  end

  it 'reabre a conversa resolvida e a mensagem entra nela' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: dona)

    expect { comecar }.not_to change(Conversation, :count)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['id']).to eq(conversa.display_id)
    expect(conversa.reload).to be_open
    expect(conversa.messages.outgoing.last.content).to eq('Oi, tudo bem?')
  end

  it 'reabre a conversa adiada e limpa o "adiada até"' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :snoozed, snoozed_until: 2.days.from_now, assignee: dona)

    comecar

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_open
    expect(conversa.snoozed_until).to be_nil
  end

  it 'mantém quem cuida e o time' do
    create(:team_member, user: dona, team: team)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: dona, team: team)

    comecar

    expect(conversa.reload).to be_open
    expect(conversa.assignee).to eq(dona)
    expect(conversa.team).to eq(team)
  end

  it 'sem ninguém cuidando, continua sem ninguém, mesmo com o rodízio da caixa ligado' do
    expect(inbox.enable_auto_assignment).to be(true)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: nil)

    comecar

    expect(conversa.reload).to be_open
    expect(conversa.assignee).to be_nil
  end

  it 'com o robô no nome, o robô continua' do
    robo = create(:agent_bot, account: account)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: nil)
    conversa.update!(ai_assignee: robo)

    comecar

    expect(conversa.reload).to be_open
    expect(conversa.ai_assignee).to eq(robo)
    expect(conversa.assignee).to be_nil
  end

  it 'conversa aberta não muda' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :open, assignee: dona)
    status_changed_at = conversa.reload.status_changed_at

    comecar

    expect(conversa.reload).to be_open
    expect(conversa.assignee).to eq(dona)
    expect(conversa.status_changed_at).to eq(status_changed_at)
  end

  it 'sem mensagem, não reabre' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: dona)

    comecar(message: nil)

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end

  it 'com a caixa criando conversas novas, a resolvida fica como está' do
    inbox.update!(lock_to_single_conversation: false)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: dona)

    expect { comecar }.to change(Conversation, :count).by(1)

    expect(conversa.reload).to be_resolved
  end

  it 'se a mensagem não sai, a conversa não reabre' do
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                     status: :resolved, assignee: dona)
    builder = instance_double(Messages::MessageBuilder)
    allow(Messages::MessageBuilder).to receive(:new).and_return(builder)
    allow(builder).to receive(:perform).and_raise(ActiveRecord::RecordInvalid.new(Message.new))

    comecar

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversa.reload).to be_resolved
  end

  it 'sem o sinal da gaveta, não reabre' do
    conversa = resolvida_da_dona

    comecar(sinal: nil)

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end

  it 'nota privada não reabre' do
    conversa = resolvida_da_dona

    comecar(message: { content: 'Anotação', private: true })

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end

  it 'robô (token de AgentBot, o n8n) não reabre, mesmo com o sinal' do
    conversa = resolvida_da_dona
    robo = create(:agent_bot, account: account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: robo)

    comecar(headers: { api_access_token: robo.access_token.token })

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end

  it 'integração com o token de API de uma pessoa não reabre, mesmo com o sinal' do
    conversa = resolvida_da_dona

    comecar(headers: { api_access_token: agent.access_token.token })

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end

  describe 'o que usa o ConversationBuilder fica como está' do
    let(:api_channel) { create(:channel_api, account: account) }
    let(:api_inbox) { api_channel.inbox.tap { |caixa| caixa.update!(lock_to_single_conversation: true) } }
    let(:api_contact_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }

    it 'o widget/API pública não reabre a conversa resolvida' do
      conversa = create(:conversation, account: account, inbox: api_inbox, contact: contact, contact_inbox: api_contact_inbox,
                                       status: :resolved)

      post "/public/api/v1/inboxes/#{api_channel.identifier}/contacts/#{api_contact_inbox.source_id}/conversations"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(conversa.display_id)
      expect(conversa.reload).to be_resolved
    end

    it 'campanhas e avisos (ConversationBuilder direto) não reabrem a conversa resolvida' do
      conversa = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                       status: :resolved)

      achada = ConversationBuilder.new(params: ActionController::Parameters.new({}), contact_inbox: contact_inbox).perform

      expect(achada).to eq(conversa)
      expect(conversa.reload).to be_resolved
    end
  end
end
