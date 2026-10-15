require 'rails_helper'

# #1433 / #1648 — um agente de outro sistema (bot de webhook do Chatwoot) plugado DEPOIS, pela API crua da caixa
# (Inbox#set_agent_bot), numa caixa só de pessoas que já tem área. Decisão do Rodrigo de 15/10 (opção B): o plug é
# aceito e a área fica. Ela continua válida e dona das conversas dela; conversa nova nasce com o agente de outro
# sistema. O risco de os dois responderem quando o outro sistema não filtra por dono ficou na #1636.
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

  it 'o plug do agente de outro sistema é aceito e ele vira o robô da caixa' do
    expect(response).to have_http_status(:ok)
    expect(AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)).to eq([externo.id])
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

  it 'conversa nova nasce com o agente de outro sistema' do
    caixa = Inbox.find(inbox.id)
    nova = create(:conversation, account: account, inbox: caixa)

    expect(caixa.agent_bot).to eq(externo)
    expect(caixa.active_bot?).to be(true)
    expect(nova.reload.assignee_agent_bot_id).to eq(externo.id)
    expect(Autonomia::Agents::QuemResponde.agent_inbox(nova)).to be_nil
  end

  it 'soltar a área devolve as conversas dela a quem atende primeiro: o agente de outro sistema' do
    described_class.desvincular!(agent: da_equipe, inbox: inbox)

    expect(da_area.reload.assignee_agent_bot_id).to eq(externo.id)
  end
end
