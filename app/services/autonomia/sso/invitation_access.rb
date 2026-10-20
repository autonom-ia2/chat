# The access a pending invitation gives, checked again when it is accepted, against what the inviter can do now
# (#1931). Without a role, or when the inviter is no longer an administrator, it makes an agent. The custom role must be
# of this account, with the feature on, and still within the inviter's reach; anything else is dropped.
class Autonomia::Sso::InvitationAccess
  def initialize(account, pending_invitation)
    @account = account
    @invitation = pending_invitation
    @inviter = account.account_users.find_by(user_id: pending_invitation['invited_by_user_id'])
  end

  def apply(account_user)
    account_user.role = administrator_asked? && @inviter&.administrator? ? 'administrator' : 'agent'
    account_user.custom_role_id = custom_role.id if custom_role
    account_user.inviter_id ||= @invitation['invited_by_user_id']
  end

  private

  def administrator_asked?
    @invitation.fetch('role', nil) == 'administrator'
  end

  def custom_role
    return @custom_role if defined?(@custom_role)

    @custom_role = find_custom_role
  end

  def find_custom_role
    custom_role_id = @invitation['custom_role_id']
    return if @inviter.blank? || custom_role_id.blank? || !@account.feature_enabled?('custom_roles')

    role = @account.custom_roles.for_people.find_by(id: custom_role_id)
    role if role && CustomRoles::GrantGuard.new(actor: @inviter).reach?(role.permissions)
  end
end
