require 'rails_helper'

RSpec.describe Autonomia::Agents::SoftDelete do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agent', agent_type: 'custom',
                                    status: :active, enabled: true, instruction: 'Private instruction.')
  end
  let(:service) { described_class.new(agent: agent, actor: actor, request_id: 'delete-request') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  it 'preserves instructions, knowledge, tools, versions and build history' do
    source = agent.sources.create!(account: account, source_type: 'txt', reference: 'faq.txt')
    entry = agent.knowledge_entries.create!(account: account, source: source, content: 'Private knowledge.')
    tool = agent.tools.create!(account: account, name: 'Search', slug: 'search', endpoint_url: 'https://example.com/search')
    version = agent.record_instruction_version!(reason: 'manual_edit', created_by: actor)
    thread = agent.build_threads.create!(account: account)

    service.perform

    expect(agent.reload).to have_attributes(deleted_by_id: actor.id, enabled: false, status: 'paused', instruction: 'Private instruction.')
    expect(agent.deleted_at).to be_present
    expect(source.reload.autonomia_agent_id).to eq(agent.id)
    expect(entry.reload.content).to eq('Private knowledge.')
    expect(tool.reload.autonomia_agent_id).to eq(agent.id)
    expect(version.reload.instruction).to eq('Private instruction.')
    expect(thread.reload.autonomia_agent_id).to eq(agent.id)
  end

  it 'records the actor, timestamp and request in a durable audit without sensitive content' do
    service.perform

    audit = Audited.audit_class.where(auditable: agent, action: 'destroy').sole
    expect(audit).to have_attributes(user_id: actor.id, associated_id: account.id, request_uuid: 'delete-request')
    expect(audit.audited_changes).to include('event' => 'autonomia.agent.soft_deleted', 'actor_id' => actor.id,
                                           'deleted_at' => agent.reload.deleted_at.iso8601(6), 'reason' => 'user_request')
    expect(audit.audited_changes.to_json).not_to include('Private instruction.', 'Private knowledge.')
  end

  it 'logs metadata only after the deletion transaction commits' do
    service
    allow(Rails.logger).to receive(:info)
    allow(ActiveRecord).to receive(:after_all_transactions_commit).and_yield
    expect(Rails.logger).to receive(:info).with(a_string_including('autonomia.agent.soft_deleted', 'delete-request'))

    service.perform
  end

  it 'does not overwrite the original actor or timestamp when called again' do
    service.perform
    deleted_at = agent.reload.deleted_at

    expect(service.perform).to be(false)
    expect(agent.reload.deleted_at).to eq(deleted_at)
    expect(Audited.audit_class.where(auditable: agent, action: 'destroy').count).to eq(1)
  end

  it 'rolls back deletion when the audit cannot be persisted' do
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)

    expect { service.perform }.to raise_error(ActiveRecord::StatementInvalid)
    expect(agent.reload).to have_attributes(deleted_at: nil, deleted_by_id: nil, enabled: true, status: 'active')
  end

  it 'archives links, preserves the historical bot and releases conversations and the inbox' do
    inbox = create(:inbox, account: account)
    connector = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox)
    link = connector.perform(connect: true).agent_inbox
    conversation = create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot_id: link.agent_bot_id)
    message = create(:message, account: account, inbox: inbox, conversation: conversation,
                               sender: link.agent_bot, message_type: :outgoing)

    service.perform

    expect(link.reload.deleted_at).to be_present
    expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    expect(AgentBot.exists?(link.agent_bot_id)).to be(true)
    expect(message.reload.sender_id).to eq(link.agent_bot_id)
    expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
    expect(Autonomia::Agents::Operate.authorized_agent_inbox(conversation)).to be_nil
  end

  it 'allows a replacement agent to connect without losing the previous link' do
    inbox = create(:inbox, account: account)
    old_link = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true).agent_inbox
    service.perform
    replacement = Autonomia::Agents::Agent.create!(account: account, name: 'Replacement', agent_type: 'custom', status: :active, enabled: true)

    result = Autonomia::Agents::Operate::InboxConnector.new(agent: replacement, inbox: inbox).perform(connect: true)

    expect(result).to be_success
    expect(old_link.reload.deleted_at).to be_present
    expect(Autonomia::Agents::AgentInbox.where(inbox_id: inbox.id).count).to eq(2)
    expect(Autonomia::Agents::AgentInbox.kept.find_by!(inbox_id: inbox.id).agent).to eq(replacement)
    expect(create(:conversation, account: account, inbox: inbox).assignee_agent_bot_id).to eq(result.agent_inbox.agent_bot_id)
  end

  it 'also disables a paused agent with stale mirror state' do
    inbox = create(:inbox, account: account)
    link = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true).agent_inbox
    agent.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations

    service.perform

    expect(link.reload.deleted_at).to be_present
    expect(inbox.reload.active_bot?).to be(false)
  end

  it 'blocks connecting a deleted agent even if it is enabled by a direct data edit' do
    service.perform
    agent.update_columns(enabled: true, status: Autonomia::Agents::Agent.statuses[:active]) # rubocop:disable Rails/SkipsModelValidations
    inbox = create(:inbox, account: account)

    result = Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true)

    expect(result.error).to eq(:agent_not_active)
    expect(agent).not_to be_operating
  end

  it 'keeps queued knowledge and builder jobs from running for a deleted agent' do
    source = agent.sources.create!(account: account, source_type: 'txt', reference: 'faq.txt')
    thread = agent.build_threads.create!(account: account)
    token = thread.begin_build!
    service.perform
    expect(Autonomia::Agents::Knowledge::Ingestor).not_to receive(:new)
    expect(Autonomia::Agents::Knowledge::Reviewer).not_to receive(:recompute_overall!)
    expect(Autonomia::Agents::Knowledge::InstructionRefresher).not_to receive(:call)
    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread.reload)
    expect(builder).not_to receive(:client)

    Autonomia::Agents::Knowledge::IngestJob.new.perform(source.id)
    Autonomia::Agents::Knowledge::ProcessJob.new.perform(source.id, 'pending-token')
    Autonomia::Agents::Knowledge::RecomputeOverallJob.new.perform(agent.id)
    Autonomia::Agents::Knowledge::RefreshInstructionJob.new.perform(agent.id, 'pending-token', 'kb_change')
    builder.run!(token)

    expect(thread.reload).to be_failed
    expect(thread.state['error']).to eq('agent_deleted')
    expect(source.reload).to be_pending
  end
end
