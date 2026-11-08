# Who may change another member's access (#1931). An administrator manages everyone; a person with people_manage
# manages agents only. Nobody changes their own role, custom role or membership, so the last administrator always
# stays. Only an administrator makes someone an administrator. Failures answer 401, like the policies.
class AccountUsers::AccessGuard
  def initialize(actor:)
    @actor = actor
  end

  # Any edit of another member (name included): administrators are off limits to non-administrators.
  def manage!(target)
    deny! if target.administrator? && !@actor.administrator?
  end

  # Changing someone's role, custom role or membership: never one's own, never an administrator's unless an administrator.
  def touch_access!(target)
    deny! if target.id == @actor.id
    manage!(target)
  end

  def change_role!(target, role)
    return if role.blank? || same_role?(target, role)

    touch_access!(target)
    assign_role!(role)
  end

  def remove!(target)
    touch_access!(target)
  end

  # A non-administrator only hands out the agent role, spelled out: any other value ("administrator", 1, "1.0") is
  # refused, so the enum's integer casting can never be used to promote someone.
  def assign_role!(role)
    deny! unless role.blank? || role.to_s == 'agent' || @actor.administrator?
  end

  private

  def same_role?(target, role)
    [target.role, AccountUser.roles[target.role].to_s].include?(role.to_s)
  end

  def deny!
    raise Pundit::NotAuthorizedError
  end
end
