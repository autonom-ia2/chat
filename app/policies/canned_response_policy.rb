# Admins and plain agents keep the upstream behaviour: any member manages canned responses.
# A custom role needs canned_response_manage to create, edit or delete them (#452).
class CannedResponsePolicy < ApplicationPolicy
  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  private

  def manage?
    account_user&.custom_role_id.blank? || account_user.permission_granted?('canned_response_manage')
  end
end
