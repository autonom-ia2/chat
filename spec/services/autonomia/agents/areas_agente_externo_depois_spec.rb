require 'rails_helper'

# #1433 / #1648 — um agente externo (bot de webhook do Chatwoot) plugado DEPOIS, pela aba "Agente externo" da caixa
# (Inbox#set_agent_bot), numa caixa só de pessoas que já tem área. Com a marcação por caixa (#1648) o plug é recusado
# (422) e nada muda: a área continua válida e dona das conversas dela, e a caixa segue aceitando área.
RSpec.describe Autonomia::Agents::Areas, type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:da_equipe) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Financeiro', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let!(:area) { described_class.vincular!(agent: da_equipe, inbox: inbox) }
  let!(:da_area) do
    create(:conversation, account: account, inbox: inbox).tap { |c| c.update!(ai_assignee: area.agent_bot, status: :open) }
  end
  let(:externo) { create(:agent_bot, account: account, name: 'Parceiro', outgoing_url: 'https://parceiro.example/webhook') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    Autonomia::Agents::Fase2.ligar!(account)
    url = "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_agent_bot"
    post url, params: { agent_bot: externo.id }, headers: admin.create_new_auth_token, as: :json
  end

  it 'o plug do agente externo é recusado e a caixa fica sem robô' do
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('caixa_com_agente_da_plataforma')
    expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
  end

  it 'a área continua válida na caixa, e a caixa segue aceitando área' do
    expect(area.reload.deleted_at).to be_nil
    expect(area).to be_valid
    expect(described_class.caixa_aceita_area?(Inbox.find(inbox.id)).codigo).to eq(:ok)
    expect(da_equipe.reload.tem_onde_trabalhar?).to be(true)
  end

  it 'a conversa de que a área é dona continua sendo respondida por ela' do
    expect(da_area.reload.assignee_agent_bot_id).to eq(area.agent_bot_id)
    expect(Autonomia::Agents::QuemResponde.agent_inbox(da_area)).to eq(area)
    expect(Autonomia::Agents::Operate.eligible_agent_inbox(da_area)).to eq(area)
  end

  it 'o agente externo não recebe o webhook das mensagens da conversa da área' do
    expect do
      create(:message, account: account, conversation: da_area, message_type: :incoming, content: 'quero o boleto')
    end.not_to have_enqueued_job(AgentBots::WebhookJob).with('https://parceiro.example/webhook', anything, anything, anything)
  end

  it 'soltar a área manda as conversas dela para as pessoas, nunca para o agente externo' do
    described_class.desvincular!(agent: da_equipe, inbox: inbox)

    expect(da_area.reload.assignee_agent_bot_id).to be_nil
  end
end
