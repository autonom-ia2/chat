require 'rails_helper'

# SEM SINAL DE VIDA (chat#585, decisão do CEO em 22/09/2026). Até aqui, dois minutos depois do pedido sem a execução
# terminar, o código publicava a frase de espera — que repetia, com outras palavras, o que a Lia tinha acabado de dizer
# (medido em produção em 21 e 22/09). Enquanto a cotação corre, nada sai sozinho: quem pergunta é respondido pela Lia.
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
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
  let(:progresso) { Autonomia::Agents::Tools::Progress }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def execucao(tool, criada:)
    register_async_tool(tool)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: tool.slug, arguments: {},
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 10.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'id' => 'cot-1' })
    run.update_columns(created_at: criada.ago) # rubocop:disable Rails/SkipsModelValidations
    run
  end

  def falas
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  it 'a cotação correndo há minutos não manda nada sozinha, em nenhuma passada' do
    tool = build_async_tool(poll: progresso.running(handle: { 'id' => 'cot-1' }))
    run = execucao(tool, criada: 3.minutes)

    described_class.new.perform(run.id, 3)
    described_class.new.perform(run.id, 4)

    expect(falas).to be_empty
    expect(run.reload.status).to eq('running')
  end

  it 'nem a passada que falha e vai tentar de novo' do
    tool = build_async_tool(poll_error: StandardError.new('portal fora'))
    run = execucao(tool, criada: 3.minutes)

    described_class.new.perform(run.id, 3)

    expect(falas).to be_empty
    expect(run.reload.status).to eq('running')
  end
end
