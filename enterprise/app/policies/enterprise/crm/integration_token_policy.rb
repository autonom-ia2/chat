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

  # A token never carries more than the person minting or rotating it holds (#2027). Sales values (#2075) are not
  # covered by crm_admin, so they follow Crm::ValorDeVenda.
  def grant_scopes?(scopes)
    Array(scopes).all? do |scope|
      scope.to_s == Crm::ValorDeVenda::CHAVE ? Crm::ValorDeVenda.ve?(account_user) : crm_permission?(scope.to_s)
    end
  end

  private

  def token_manage?
    account_user&.permission_granted?('token_manage') || false
  end
end
