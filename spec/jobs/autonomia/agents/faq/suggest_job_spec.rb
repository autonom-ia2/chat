require 'rails_helper'

# #284 (2b) — o job só extrai com a flag por agente ligada; nunca levanta.
RSpec.describe Autonomia::Agents::Faq::SuggestJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
  let(:agent_bot) { create(:agent_bot, account: account, outgoing_url: nil) }

  def create_agent(config)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.', config: config)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
    agent
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'does nothing (no extractor) when the agent has no faq_suggestions flag' do
    create_agent({})
    expect(Autonomia::Agents::Faq::Extractor).not_to receive(:new)

    described_class.new.perform(conversation.id)
  end

  it 'runs the extractor for the agent that handled the conversation when the flag is on' do
    agent = create_agent('faq_suggestions' => true)
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conversation.id, event_type: :replied)
    extractor = instance_double(Autonomia::Agents::Faq::Extractor, call: [])
    expect(Autonomia::Agents::Faq::Extractor).to receive(:new).with(agent: agent, conversation: conversation).and_return(extractor)

    described_class.new.perform(conversation.id)
  end

  # Tema 14 (#1434): o ajudante consultado na conversa não é quem a atendeu.
  it 'does not turn a helper consultation into FAQ suggestions for the helper' do
    principal = create_agent('faq_suggestions' => true)
    ajudante = Autonomia::Agents::Agent.create!(account: account, name: 'Regras', agent_type: 'custom', actuation: :internal,
                                                status: :active, enabled: true, instruction: 'Regras.',
                                                config: { 'faq_suggestions' => true })
    Autonomia::Agents::AgentEvent.create!(agent: principal, account: account, conversation_id: conversation.id, event_type: :replied)
    Autonomia::Agents::AgentEvent.create!(agent: ajudante, account: account, conversation_id: conversation.id, event_type: :consulted)
    extractor = instance_double(Autonomia::Agents::Faq::Extractor, call: [])
    allow(Autonomia::Agents::Faq::Extractor).to receive(:new).and_return(extractor)

    described_class.new.perform(conversation.id)

    expect(Autonomia::Agents::Faq::Extractor).to have_received(:new).with(agent: principal, conversation: conversation)
    expect(Autonomia::Agents::Faq::Extractor).not_to have_received(:new).with(agent: ajudante, conversation: anything)
  end

  it 'skips conversations that are no longer resolved' do
    create_agent('faq_suggestions' => true)
    conversation.update!(status: :open)
    expect(Autonomia::Agents::Faq::Extractor).not_to receive(:new)

    described_class.new.perform(conversation.id)
  end

  it 'does not extract from an archived agent referenced by a historical event' do
    agent = create_agent('faq_suggestions' => true)
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: account, conversation_id: conversation.id, event_type: :replied)
    Autonomia::Agents::SoftDelete.new(agent: agent, actor: nil).perform
    expect(Autonomia::Agents::Faq::Extractor).not_to receive(:new)

    described_class.new.perform(conversation.id)
  end

  it 'never raises when the extraction blows up' do
    create_agent('faq_suggestions' => true)
    allow(Autonomia::Agents::Faq::Extractor).to receive(:new).and_raise(StandardError, 'boom')

    expect { described_class.new.perform(conversation.id) }.not_to raise_error
  end
end
