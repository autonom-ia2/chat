class Crm::FollowUps::ReminderPopupQuery
  REMINDER_MODES = %w[reminder_only snooze_conversation].freeze

  def initialize(account:, user:, account_user:, scope: nil)
    @account = account
    @user = user
    @account_user = account_user
    @scope = scope
  end

  def perform
    visible_follow_ups.select { |follow_up| popup_eligible?(follow_up) }
  end

  private

  def visible_follow_ups
    base_scope
      .where(status: :overdue)
      .where(automation_mode: REMINDER_MODES.map { |mode| Crm::FollowUp.automation_modes[mode] })
      .order(:due_at, :id)
      .limit(25)
  end

  def base_scope
    scope = @scope || Pundit.policy_scope!(user_context, Crm::FollowUp).where(account_id: @account.id)
    scope.includes(:card, :assignee, :conversation, :contact, :inbox, :created_by)
  end

  def user_context
    { user: @user, account: @account, account_user: @account_user }
  end

  def popup_eligible?(follow_up)
    return false if Crm::FollowUps::ReminderDismisser.dismissed_for?(follow_up: follow_up, user: @user)

    recipient_ids = reminder_recipient_ids(follow_up)
    recipient_ids.include?(@user.id)
  end

  def reminder_recipient_ids(follow_up)
    Crm::FollowUps::RecipientResolver.new(follow_up).users.map(&:id)
  end
end
