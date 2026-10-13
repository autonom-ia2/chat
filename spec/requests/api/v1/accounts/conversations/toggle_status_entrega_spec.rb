require 'rails_helper'

# n8n passando a conversa por toggle_status (#1454, G3 e G4 da auditoria). Na caixa de robô a conversa nasce e segue
# aberta com o robô no nome (#1377), então "pendente → aberta" deixou de ser o único sinal de passagem.
RSpec.describe 'toggle_status como passagem do robô' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/toggle_status" }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, status: :open).reload.tap do |conv|
      conv.update!(ai_assignee: bot, assignee: nil)
    end
  end

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
  end

  def toggle(token, status: 'open')
    post path, headers: { api_access_token: token }, params: { status: status }, as: :json
  end

  # Pega G3: na caixa webhook (n8n) a conversa já está aberta com o robô; o toggle_status(open) não fazia nada.
  it 'conversa aberta com o robô no nome: a passagem acontece e quem está online recebe', :aggregate_failures do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    toggle(bot.access_token.token)

    expect(response).to have_http_status(:success)
    expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil, status: 'open')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: conversation))
  end

  it 'conversa pendente: continua sendo passagem' do
    conversation.update!(status: :pending)

    toggle(bot.access_token.token)

    expect(conversation.reload).to have_attributes(assignee_id: ana.id, status: 'open')
  end

  # Pega o reenvio do n8n: a conversa já passada e à espera não gera outra passagem (nem outra notificação à caixa).
  it 'conversa já à espera de pessoa: não passa de novo', :aggregate_failures do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    conversation.bot_handoff!
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    toggle(bot.access_token.token)

    expect(response).to have_http_status(:success)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Com uma pessoa já atribuída, o toggle(open) do robô é só troca de status: nada de passagem nem aviso à caixa.
  it 'conversa com pessoa atribuída: o toggle do robô só troca o status', :aggregate_failures do
    conversation.update!(assignee: ana, status: :pending)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    toggle(bot.access_token.token)

    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: ana.id)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
  end

  # Pega O26 (bateria do Agentes IA): o n8n reabrindo uma conversa resolvida com o robô no nome só reabre, como no main.
  it 'conversa resolvida com o robô no nome: o toggle(open) só reabre, sem passagem', :aggregate_failures do
    conversation.update!(status: :resolved)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    toggle(bot.access_token.token)

    expect(response).to have_http_status(:success)
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: nil, ai_assignee: bot)
    expect(conversation.bot_handoff_waiting?).to be(false)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
  end

  it 'robô adiando a conversa não é passagem' do
    toggle(bot.access_token.token, status: 'snoozed')

    expect(conversation.reload).to have_attributes(status: 'snoozed', assignee_id: nil)
  end

  # Pega G4 (hipótese da auditoria): o token de integração do CRM resolve para um usuário com papel de agente; se
  # chegasse ao toggle_status, o handle_human_open poria esse usuário como atendente. O portão do token nega antes.
  it 'token de integração do CRM não alcança toggle_status nem vira atendente', :aggregate_failures do
    token = Crm::IntegrationToken.create!(account: account, name: 'n8n', scopes: ['crm_admin'], created_by: admin)

    with_modified_env(CRM_KANBAN_ENABLED: 'true') { toggle(token.access_token.token) }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('This token is only authorized for CRM endpoints')
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end
end
