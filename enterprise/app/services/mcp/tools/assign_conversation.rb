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
    # find_conversation authorizes show?, which in this fork is the gate for every write to a conversation
    conversation = find_conversation(conversation_id)
    team = find_team(team_id)
    check_agent(conversation, agent_id)
    ActiveRecord::Base.transaction do
      conversation.with_lock { conversation.update!(team: team) } unless team_id.nil?
      Conversations::AssignmentService.new(conversation: conversation, assignee_id: agent_id.positive? ? agent_id : nil).perform unless agent_id.nil?
    end

    respond(conversation_summary(conversation.reload))
  end

  # Both are checked before anything is saved, so a refused agent leaves the conversation as it was.
  def self.find_team(team_id)
    Current.account.teams.find(team_id) if team_id&.positive?
  end
  private_class_method :find_team

  # Same people the dashboard offers: members of the conversation's inbox and the administrators.
  def self.check_agent(conversation, agent_id)
    return unless agent_id&.positive?
    raise ActiveRecord::RecordNotFound if conversation.inbox.assignable_agents.none? { |agent| agent.id == agent_id }
  end
  private_class_method :check_agent
end
