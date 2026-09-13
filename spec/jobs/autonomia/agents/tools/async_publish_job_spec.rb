require 'rails_helper'

# OS DOIS TETOS DO `AsyncPublishJob` (rodada 2 da fatia 1 do PDF rápido, 13/09/2026). A cadeia do turno
# deixa de ser esperada em `MAX_PUBLISH_DEFERRALS`; a entrega de que um texto encadeado depende, em
# `MAX_DEPENDENCY_DEFERRALS`. O job reenfileira a forma que o publicador devolveu em `adiada`.
RSpec.describe Autonomia::Agents::Tools::AsyncPublishJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                     scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id,
                                              origin_message_id: 77 })
                              .tap { |r| r.promote!(expected_chunks: 2, notify_customer: false, expires_at: 3.minutes.from_now) }
  end
  let(:config) { Autonomia::Agents::Tools::AsyncConfig }
  let(:dependencia) { run.delivery_token('arquivo:https://arquivos.exemplo.test/comparativo.pdf') }
  let(:fecho) { Autonomia::Agents::Tools::EntregaEncadeada.forma('Encerrei a busca.', depois_de: dependencia) }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  def bot_messages = conversation.messages.reload.where(sender_type: 'AgentBot')

  def reenfileirados
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job['job_class'] == described_class.name }
                   .map { |job| ActiveJob::Arguments.deserialize(job['arguments']) }
  end

  it 'com a cadeia no teto e sem a dependencia, reenfileira o texto encadeado com mais um adiamento' do
    # Act
    described_class.new.perform(run.id, fecho, config::MAX_PUBLISH_DEFERRALS)

    # Assert
    expect(bot_messages).to be_empty
    expect(reenfileirados).to eq([[run.id, fecho, config::MAX_PUBLISH_DEFERRALS + 1]])
  end

  it 'no teto da dependencia, publica o texto encadeado sem ela' do
    # Act
    described_class.new.perform(run.id, fecho, config::MAX_DEPENDENCY_DEFERRALS)

    # Assert
    expect(bot_messages.sole.content).to eq('Encerrei a busca.')
    expect(reenfileirados).to be_empty
  end

  it 'um texto comum sai no teto da cadeia, sem esperar o teto da dependencia' do
    # Act
    described_class.new.perform(run.id, 'encontrei 3 opções', config::MAX_PUBLISH_DEFERRALS)

    # Assert
    expect(bot_messages.sole.content).to eq('encontrei 3 opções')
    expect(reenfileirados).to be_empty
  end
end
