require 'rails_helper'

# #1433 — a conversa mudou de dono (Fase 2: passou para a área) no meio de uma consulta assíncrona do agente que a
# disparou. A autorização de agora é de OUTRO vínculo: a execução para com recusa nomeada, sem consultar o portal
# de novo e sem publicar nada (antes seguia até o teto e a publicação recusava no fim).
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:da_equipe) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Financeiro', agent_type: 'custom', status: :active, enabled: true)
  end
  let(:porta) do
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true).agent_inbox
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def submitted_run
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: { 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: porta.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'id' => 'cot-1' })
    run
  end

  it 'para com vinculo_mudou, sem consultar o portal, quando a conversa passou para a área' do
    consultas = []
    consultar = lambda do |attempt|
      consultas << attempt
      Autonomia::Agents::Tools::Progress.running
    end
    register_async_tool(build_async_tool(poll: consultar))
    run = submitted_run
    Autonomia::Agents::Fase2.ligar!(account)
    area = Autonomia::Agents::Areas.vincular!(agent: da_equipe, inbox: inbox)
    conversation.update!(ai_assignee: area.agent_bot, status: :open)

    described_class.new.perform(run.id, 1)

    expect(consultas).to be_empty
    expect(run.reload).to have_attributes(status: 'blocked', failure_code: 'vinculo_mudou')
    expect(conversation.messages.where(sender_type: 'AgentBot')).to be_empty
    expect(described_class).not_to have_been_enqueued
  end

  it 'segue normal quando o dono continua o mesmo' do
    register_async_tool(build_async_tool(poll: Autonomia::Agents::Tools::Progress.running))
    run = submitted_run
    Autonomia::Agents::Fase2.ligar!(account)

    described_class.new.perform(run.id, 1)

    expect(run.reload.status).to eq('running')
  end
end
