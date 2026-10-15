class Conversations::AssignmentService
  def initialize(conversation:, assignee_id:, assignee_type: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
  end

  def perform
    agent_bot_assignment? ? assign_agent_bot : assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type

  def assign_agent
    conversation.with_lock do
      if open_on_assignment? && conversation.pending?
        conversation.status = :open
        conversation.waiting_since = Time.current if conversation.waiting_since.blank?
      end
      conversation.assignee = assignee
      conversation.ai_assignee = nil
      hand_back_to_inbox_bot if assignee.nil?
      conversation.save!
    end
    assignee
  end

  # Desatribuir numa caixa com robô devolve a conversa a ele (#1377): sem pessoa, quem atende é o robô. Conversa de
  # robô nunca fica pendente. Com a Fase 2, volta ao agente responsável pelo funil, se houver (#1606).
  def hand_back_to_inbox_bot
    conversation.ai_assignee = Autonomia::Agents::QuemResponde.robo_da_devolucao(conversation)
    conversation.status = :open if conversation.ai_assignee.present? && conversation.pending?
  end

  def assign_agent_bot
    assign_ai_assignee(agent_bot)
  end

  def open_on_assignment?
    assignee.present? && conversation.ai_assignee_type.present?
  end

  def assign_ai_assignee(ai_assignee)
    return unless ai_assignee

    conversation.with_lock do
      conversation.assignee = nil
      conversation.ai_assignee = ai_assignee
      # Conversa de robô nunca fica pendente (#1377, regra do Rodrigo): o robô atende a conversa aberta, então
      # entregar a ele uma conversa resolvida ou adiada a reabre. O Captain, que exigiria pendente, não é usado.
      conversation.status = :open
      conversation.snoozed_until = nil
      # Entregar de novo a um robô encerra a espera de pessoa de uma passagem anterior.
      conversation.end_bot_handoff_wait
      conversation.save!
    end
    ai_assignee
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  def agent_bot
    @agent_bot ||= AgentBot.accessible_to(conversation.account).find_by(id: assignee_id)
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end

Conversations::AssignmentService.prepend_mod_with('Conversations::AssignmentService')
