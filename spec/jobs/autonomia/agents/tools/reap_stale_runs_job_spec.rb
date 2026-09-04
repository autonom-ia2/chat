require 'rails_helper'

# O varredor existe porque a execução assíncrona avança por uma corrente de jobs que se re-agendam.
# Quando a corrente se rompe (worker morto num deploy, enqueue perdido com o Redis fora), ninguém
# mais olha para a linha — e o cliente fica esperando uma cotação que não vai acontecer.
RSpec.describe Autonomia::Agents::Tools::ReapStaleRunsJob, type: :job do
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

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def open_run(origin_message_id: nil)
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                     scope: { conversation_id: conversation.id,
                                              agent_inbox_id: agent_inbox.id,
                                              origin_message_id: origin_message_id })
  end

  def bot_contents
    conversation.reload.messages.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  it 'closes an abandoned run and tells the customer, instead of leaving it waiting forever' do
    # Arrange — execução viva cujo prazo venceu com folga e cujo job nunca mais rodou
    register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.ago)

    # Act
    described_class.new.perform

    # Assert
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
    expect(bot_contents).to eq(['não consegui concluir a consulta'])
  end

  it 'stays silent when the customer already received a delivery' do
    # Arrange
    register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.ago)
    run.record_delivery!

    # Act
    described_class.new.perform

    # Assert — fecha a linha, mas não contradiz o que o cliente já leu
    expect(run.reload.status).to eq('failed')
    expect(bot_contents).to be_empty
  end

  it 'leaves a run alone while it is still within its deadline plus the grace window' do
    # Arrange
    register_async_tool(build_async_tool)
    run = open_run
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)

    # Act
    described_class.new.perform

    # Assert — venceu, mas ainda dentro da folga: um poll legítimo pode estar prestes a rodar
    expect(run.reload.status).to eq('running')
  end

  it 'discards a pending run that no dispatcher ever picked up, without talking to the customer' do
    # Arrange — o worker morreu entre o aceite e o despacho
    run = open_run
    run.update!(created_at: 2.hours.ago)

    # Act
    described_class.new.perform

    # Assert
    expect(run.reload.status).to eq('discarded')
    expect(bot_contents).to be_empty
  end
end
