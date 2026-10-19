class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  # Porta de toda escrita na conversa. Leitura usa view? (#1800).
  def show?
    member_access?
  end

  # Começar conversa nova: a caixa já é conferida no controller. O EE pergunta e recusa quem só lê (#1800).
  def create?
    true
  end

  # Ler a conversa (GET). No OSS é o mesmo que show?; o EE também deixa passar quem só lê (conversation_view).
  def view?
    show?
  end

  private

  def member_access?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  # Caixa ou time, e o funil do card libera (#1148): o acesso por funil vale também para quem chega pelo time.
  def agent_can_view_conversation?
    (inbox_access? || team_access?) && Crm::Access::ConversationScope.new(user: user, account: account, account_user: account_user).allows?(record)
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
