# Resolve o destino no instante da passagem. O roteador só conhece os três destinos do painel;
# CRM, devolução por pausa/exclusão e remoção de canal continuam em seus próprios caminhos.
class Autonomia::Agents::Operate::HandoffRouter
  TARGET_TYPES = %w[any member team].freeze

  def initialize(agent:, conversation:, agent_inbox:)
    @agent = agent
    @conversation = conversation
    @agent_inbox = agent_inbox
  end

  def route
    return invalid_target if target_type != 'any' && !same_account_context?

    case target_type
    when 'any' then target_any
    when 'member' then route_member
    when 'team' then route_team
    else invalid_target
    end
  end

  private

  attr_reader :agent, :conversation, :agent_inbox

  def same_account_context?
    agent.account_id == conversation.account_id && agent_inbox&.account_id == conversation.account_id
  end

  def target_type
    value = agent.config.to_h['handoff_target_type'].to_s
    value.presence || 'any'
  end

  def target_id
    value = agent.config.to_h['handoff_target_id']
    id = Integer(value.to_s, 10)
    id.positive? ? id : nil
  rescue ArgumentError, TypeError
    nil
  end

  def route_member
    return invalid_target unless target_id
    return invalid_target unless agent_inbox&.inbox_id == conversation.inbox_id

    member = persisted_conversation.inbox.assignable_agents.find { |user| user.id == target_id }
    return invalid_target unless member

    ::Conversations::AssignmentService.new(conversation: persisted_conversation, assignee_id: member.id).perform
    target(type: 'member', id: member.id, name: member.name)
  end

  def route_team
    return invalid_target unless target_id

    team = Team.where(account_id: agent.account_id).find_by(id: target_id)
    return invalid_target unless team

    # AssignmentHandler/AutoAssignmentHandler keeps the automatic choice inside the team's
    # members and leaves assignee nil when distribution is off or nobody is available.
    conversation = persisted_conversation
    native_open = native_open_conversation?(conversation)
    same_team = conversation.team_id == team.id

    # A native mirror keeps ai_assignee_type present until bot_handoff!, but the assignment
    # callback intentionally skips bot-owned conversations. Clear that ownership in the same
    # write as the team change so the existing callback can choose an eligible team member.
    conversation.ai_assignee = nil if native_open
    conversation.update!(team: team)
    assign_same_team_native_conversation(conversation, team) if native_open && same_team
    target(type: 'team', id: team.id, name: team.name)
  end

  def native_open_conversation?(candidate)
    candidate.open? && candidate.ai_assignee_type.present? &&
      candidate.assignee_agent_bot_id == agent_inbox&.agent_bot_id
  end

  def assign_same_team_native_conversation(conversation, team)
    return unless team.allow_auto_assign?

    allowed_agent_ids = conversation.inbox.member_ids_with_assignment_capacity & team.members.ids
    return if allowed_agent_ids.empty?

    ::AutoAssignment::AgentAssignmentService.new(
      conversation: conversation, allowed_agent_ids: allowed_agent_ids
    ).perform
  end

  def persisted_conversation
    @persisted_conversation ||= conversation.class.find(conversation.id)
  end

  def target_any
    target(type: 'any')
  end

  def target(type:, id: nil, name: nil)
    { type: type, id: id, name: name }
  end

  def invalid_target
    Rails.logger.warn("[autonomia][handoff] alvo_invalido agent=#{agent.id} conversation=#{conversation.id}")
    target_any
  end
end
