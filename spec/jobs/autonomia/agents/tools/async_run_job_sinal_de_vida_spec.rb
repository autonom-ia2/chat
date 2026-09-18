require 'rails_helper'

# O SINAL DE VIDA (fatia 3 do #420, decisão do CEO): a cotação não publica mais preço enquanto corre. Passados dois
# minutos do pedido sem a execução terminar, sai UMA mensagem, a frase de espera; se ela termina antes, nada.
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
  let(:correndo) { build_async_tool(poll: progresso.running(handle: { 'id' => 'cot-1' })) }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  def execucao(tool, criada:)
    register_async_tool(tool)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: tool.slug, arguments: {},
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 5.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'id' => 'cot-1' })
    run.update_columns(created_at: criada.ago) # rubocop:disable Rails/SkipsModelValidations
    run
  end

  def falas
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  it 'antes dos dois minutos, nada sai' do
    run = execucao(correndo, criada: 119.seconds)

    described_class.new.perform(run.id, 3)

    expect(falas).to be_empty
    expect(run.reload.handle).not_to have_key(described_class::SINAL_DE_VIDA_KEY)
  end

  it 'passados os dois minutos, sai a frase de espera, uma vez so' do
    run = execucao(correndo, criada: 121.seconds)

    described_class.new.perform(run.id, 3)
    described_class.new.perform(run.id, 4)

    expect(falas).to eq([correndo.waiting_message])
    expect(run.reload.delivered_count).to eq(0)
  end

  it 'a execucao que termina na passada nao manda o sinal' do
    tool = build_async_tool(poll: progresso.done(deliveries: ['o resultado'], handle: { 'id' => 'cot-1' }), resultado: true)
    run = execucao(tool, criada: 5.minutes)

    described_class.new.perform(run.id, 3)

    expect(falas).not_to include(tool.waiting_message)
  end

  it 'a passada que falha e vai tentar de novo tambem manda o sinal' do
    tool = build_async_tool(poll_error: StandardError.new('portal fora'))
    run = execucao(tool, criada: 3.minutes)

    described_class.new.perform(run.id, 3)

    expect(falas).to eq([tool.waiting_message])
    expect(run.reload.status).to eq('running')
  end
end
