class Crm::IntegrationTokenPolicy < ApplicationPolicy
  # CRM integration tokens are an admin-grade credential: only administrators may
  # mint/list/revoke them. The EE overlay (Enterprise::Crm::IntegrationTokenPolicy)
  # relaxes this to crm_admin via the CrmPermissions concern.
  def index?
    administrator?
  end

  def create?
    administrator?
  end

  def destroy?
    administrator?
  end

  def rotate?
    administrator?
  end

  def grant_scopes?(_scopes)
    administrator?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end

Crm::IntegrationTokenPolicy.prepend_mod_with('Crm::IntegrationTokenPolicy')
