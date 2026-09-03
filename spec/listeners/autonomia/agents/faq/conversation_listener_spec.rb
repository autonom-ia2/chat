require 'rails_helper'

# #284 (2b) — só enfileira a extração quando a caixa tem agente Autonom.ia COM a flag ligada.
RSpec.describe Autonomia::Agents::Faq::ConversationListener do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
  let(:agent_bot) { create(:agent_bot, account: account, outgoing_url: nil) }

  def connect_agent(config)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.', config: config)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  def event
    Events::Base.new('conversation_resolved', Time.current, conversation: conversation)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'enqueues the job for an agent with the flag on' do
    connect_agent('faq_suggestions' => true)

    expect { described_class.instance.conversation_resolved(event) }
      .to have_enqueued_job(Autonomia::Agents::Faq::SuggestJob).with(conversation.id)
  end

  it 'enqueues nothing without the flag (default) or without an agent on the inbox' do
    connect_agent({})
    resolved = event # força os lets antes do bloco (criar a conversa enfileira jobs do core)

    expect { described_class.instance.conversation_resolved(resolved) }
      .not_to have_enqueued_job(Autonomia::Agents::Faq::SuggestJob)

    Autonomia::Agents::AgentInbox.delete_all
    expect { described_class.instance.conversation_resolved(resolved) }
      .not_to have_enqueued_job(Autonomia::Agents::Faq::SuggestJob)
  end
end
