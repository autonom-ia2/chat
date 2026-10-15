require 'rails_helper'

# #1433 — REGISTRO do comportamento de hoje, sem bloqueio: um agente externo (bot de webhook do Chatwoot, plugado pelo
# painel com Inbox#set_agent_bot / AgentBotInbox) entra DEPOIS numa caixa só de pessoas que já tem área. O painel não
# passa pelo Areas e não trava a caixa. Barrar isso é do próximo PR, a marcação por caixa (decisão do Rodrigo de 15/10).
# Quando a marcação entrar, os `pending` daqui viram o comportamento esperado.
RSpec.describe Autonomia::Agents::Areas do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
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
    AgentBotInbox.create!(inbox: inbox, agent_bot: externo, account: account)
  end

  it 'a área continua na caixa, mas o vínculo dela deixa de ser válido e a caixa passa a recusar área' do
    expect(area.reload.deleted_at).to be_nil
    expect(area).not_to be_valid
    expect(area.errors[:papel]).to be_present
    expect(described_class.caixa_aceita_area?(Inbox.find(inbox.id)).codigo).to eq(:robo_externo)
    expect(da_equipe.reload.tem_onde_trabalhar?).to be(true)
  end

  it 'a conversa de que a área é dona continua sendo respondida por ela' do
    expect(Autonomia::Agents::QuemResponde.agent_inbox(da_area)).to eq(area)
    expect(Autonomia::Agents::Operate.eligible_agent_inbox(da_area)).to eq(area)
  end

  it 'o agente externo também recebe o webhook das mensagens da conversa da área (pode haver resposta dupla)' do
    expect do
      create(:message, account: account, conversation: da_area, message_type: :incoming, content: 'quero o boleto')
    end.to have_enqueued_job(AgentBots::WebhookJob).with('https://parceiro.example/webhook', anything, :agent_bot_webhook,
                                                         hash_including(:secret, :delivery_id))
  end

  it 'conversa nova nasce com o agente externo, não com a área' do
    nova = create(:conversation, account: account, inbox: inbox)

    expect(nova.assignee_agent_bot_id).not_to eq(area.agent_bot_id)
    expect(Autonomia::Agents::QuemResponde.agent_inbox(nova)).to be_nil
  end

  it 'soltar a área hoje entrega as conversas dela ao agente externo' do
    described_class.desvincular!(agent: da_equipe, inbox: inbox)

    expect(da_area.reload.assignee_agent_bot_id).to eq(externo.id)
  end

  it 'soltar a área deveria mandar as conversas dela para as pessoas, nunca para o agente externo' do
    pending 'marcação por caixa (próximo PR): devolver_conversas_a_porta! usa inbox.agent_bot, que aqui é o agente externo'
    described_class.desvincular!(agent: da_equipe, inbox: inbox)

    expect(da_area.reload.assignee_agent_bot_id).to be_nil
  end
end
