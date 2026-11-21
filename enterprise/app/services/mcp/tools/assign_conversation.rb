class Mcp::Tools::AssignConversation < Mcp::Tools::Base
  tool_name 'assign_conversation'
  description 'Assign a conversation to an agent and/or a team, or remove them. Get ids from list_agents and list_teams. ' \
              'Pass 0 to remove the agent or the team. Only the fields you pass are changed.'
  scope 'conversations:write'
  annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
  input_schema(
    properties: {
      conversation_id: { type: 'integer', description: 'The conversation id from list_conversations.' },
      agent_id: { type: 'integer', minimum: 0, description: 'The agent id from list_agents. 0 removes the agent.' },
      team_id: { type: 'integer', minimum: 0, description: 'The team id from list_teams. 0 removes the team.' }
    },
    required: ['conversation_id']
  )

  def self.perform(conversation_id:, agent_id: nil, team_id: nil)
    conversation = find_conversation(conversation_id)
    authorize(conversation, :update?)
    assign_team(conversation, team_id) unless team_id.nil?
    assign_agent(conversation, agent_id) unless agent_id.nil?

    respond(conversation_summary(conversation.reload))
  end

  # Same people the dashboard offers: members of the conversation's inbox and the administrators.
  def self.assign_agent(conversation, agent_id)
    raise ActiveRecord::RecordNotFound if agent_id.positive? && conversation.inbox.assignable_agents.none? { |agent| agent.id == agent_id }

    Conversations::AssignmentService.new(conversation: conversation, assignee_id: agent_id.positive? ? agent_id : nil).perform
  end
  private_class_method :assign_agent

  def self.assign_team(conversation, team_id)
    team = team_id.positive? ? Current.account.teams.find(team_id) : nil
    conversation.with_lock { conversation.update!(team: team) }
  end
  private_class_method :assign_team
end
