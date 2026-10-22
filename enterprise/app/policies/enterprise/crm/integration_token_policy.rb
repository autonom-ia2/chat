module Enterprise::Crm::IntegrationTokenPolicy
  include CrmPermissions

  # CRM integration tokens are secrets the platform issues: admin or token_manage (#2027).
  def index?
    token_manage?
  end

  def create?
    token_manage?
  end

  def destroy?
    token_manage?
  end

  def rotate?
    token_manage?
  end

  # A token never carries more than the person minting or rotating it holds (#2027).
  def grant_scopes?(scopes)
    Array(scopes).all? { |scope| crm_permission?(scope.to_s) }
  end

  private

  def token_manage?
    account_user&.permission_granted?('token_manage') || false
  end
end
