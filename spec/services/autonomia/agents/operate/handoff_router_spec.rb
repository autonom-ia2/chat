require 'rails_helper'

RSpec.describe Autonomia::Agents::Operate::HandoffRouter, type: :service do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda.', config: config)
  end
  let(:agent_bot) { create(:agent_bot, account: account, outgoing_url: nil) }
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:config) { {} }

  def route(conversation_record = conversation)
    described_class.new(agent: agent, conversation: conversation_record, agent_inbox: agent_inbox).route
  end

  it 'assigns a valid member from the conversation inbox, including an administrator' do
    administrator = create(:user, account: account, role: :administrator)
    agent.update!(config: { 'handoff_target_type' => 'member', 'handoff_target_id' => administrator.id })

    target = route

    expect(target).to include(type: 'member', id: administrator.id, name: administrator.name)
    expect(conversation.reload.assignee).to eq(administrator)
  end

  it 'assigns a valid account team and leaves the conversation unassigned when auto assignment is off' do
    team = create(:team, account: account, allow_auto_assign: false)
    native_conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, ai_assignee: agent_bot)
    agent.update!(config: { 'handoff_target_type' => 'team', 'handoff_target_id' => team.id })

    target = route(native_conversation)

    expect(target).to include(type: 'team', id: team.id, name: team.name)
    expect(native_conversation.reload.team).to eq(team)
    expect(native_conversation.reload).to have_attributes(assignee: nil, assignee_agent_bot_id: nil)
  end

  it 'assigns an eligible member when an open native conversation is handed to a new team' do
    team = create(:team, account: account, allow_auto_assign: true)
    eligible = create(:user, account: account, role: :agent, auto_offline: false)
    outside_team = create(:user, account: account, role: :agent, auto_offline: false)
    native_conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, ai_assignee: agent_bot)
    create(:inbox_member, inbox: inbox, user: eligible)
    create(:inbox_member, inbox: inbox, user: outside_team)
    create(:team_member, team: team, user: eligible)
    agent.update!(config: { 'handoff_target_type' => 'team', 'handoff_target_id' => team.id })

    round_robin = instance_double(AutoAssignment::InboxRoundRobinService)
    allow(AutoAssignment::InboxRoundRobinService).to receive(:new).and_return(round_robin)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
      eligible.id.to_s => 'online', outside_team.id.to_s => 'online'
    )
    expect(round_robin).to receive(:available_agent).with(allowed_agent_ids: [eligible.id.to_s]).and_return(eligible)

    target = route(native_conversation)

    expect(target).to include(type: 'team', id: team.id, name: team.name)
    expect(native_conversation.reload).to have_attributes(status: 'open', team: team, assignee: eligible, assignee_agent_bot_id: nil)
    expect(native_conversation.reload.assignee).not_to eq(outside_team)
  end

  it 'assigns an eligible member when the open native conversation already has the target team' do
    team = create(:team, account: account, allow_auto_assign: true)
    eligible = create(:user, account: account, role: :agent, auto_offline: false)
    native_conversation = create(
      :conversation, account: account, inbox: inbox, team: team, assignee: nil, ai_assignee: agent_bot
    )
    create(:inbox_member, inbox: inbox, user: eligible)
    create(:team_member, team: team, user: eligible)
    agent.update!(config: { 'handoff_target_type' => 'team', 'handoff_target_id' => team.id })

    round_robin = instance_double(AutoAssignment::InboxRoundRobinService)
    allow(AutoAssignment::InboxRoundRobinService).to receive(:new).and_return(round_robin)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(eligible.id.to_s => 'online')
    expect(round_robin).to receive(:available_agent).with(allowed_agent_ids: [eligible.id.to_s]).and_return(eligible)

    route(native_conversation)

    expect(native_conversation.reload).to have_attributes(
      status: 'open', team: team, assignee: eligible, assignee_agent_bot_id: nil
    )
  end

  it 'leaves an open native conversation unassigned when no team member has capacity' do
    team = create(:team, account: account, allow_auto_assign: true)
    eligible = create(:user, account: account, role: :agent, auto_offline: false)
    native_conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, ai_assignee: agent_bot)
    create(:team_member, team: team, user: eligible)
    agent.update!(config: { 'handoff_target_type' => 'team', 'handoff_target_id' => team.id })
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(eligible.id.to_s => 'online')

    route(native_conversation)

    expect(native_conversation.reload).to have_attributes(
      status: 'open', team: team, assignee: nil, assignee_agent_bot_id: nil
    )
  end

  it 'leaves an open native conversation unassigned when the inbox member is offline' do
    team = create(:team, account: account, allow_auto_assign: true)
    eligible = create(:user, account: account, role: :agent, auto_offline: true)
    native_conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, ai_assignee: agent_bot)
    create(:team_member, team: team, user: eligible)
    create(:inbox_member, inbox: inbox, user: eligible)
    agent.update!(config: { 'handoff_target_type' => 'team', 'handoff_target_id' => team.id })
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})

    route(native_conversation)

    expect(native_conversation.reload).to have_attributes(
      status: 'open', team: team, assignee: nil, assignee_agent_bot_id: nil
    )
  end

  it 'falls back to any and logs a sanitized code for an invalid member target' do
    agent.update!(config: { 'handoff_target_type' => 'member', 'handoff_target_id' => 999_999 })
    expect(Rails.logger).to receive(:warn).with(a_string_matching(/\[autonomia\]\[handoff\] alvo_invalido/))

    expect(route).to include(type: 'any', id: nil, name: nil)
    expect(conversation.reload.assignee).to be_nil
  end

  it 'keeps the baseline any target when no target is configured' do
    expect(route).to eq(type: 'any', id: nil, name: nil)
  end

  it 'does not route a target from another account' do
    foreign_account = create(:account)
    foreign_team = create(:team, account: foreign_account)
    agent.update!(config: { 'handoff_target_type' => 'team', 'handoff_target_id' => foreign_team.id })

    expect(Rails.logger).to receive(:warn).with(a_string_matching(/alvo_invalido/))
    expect(route).to eq(type: 'any', id: nil, name: nil)
    expect(conversation.reload.team).to be_nil
  end
end
