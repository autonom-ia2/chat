# Importação da identidade visual (#1076): acompanhar com campaign_view, pedir com campaign_manage.
class BrandImportJobPolicy < ApplicationPolicy
  def show?
    account_user&.permission_granted?('campaign_view') && record.account_id == account.id
  end

  def create?
    account_user&.permission_granted?('campaign_manage')
  end
end
