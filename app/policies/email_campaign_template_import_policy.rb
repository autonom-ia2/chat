# Importar modelo (#1099, delivery B): whoever manages campaigns imports, follows and saves — the same key that
# creates templates in "Meus modelos". Imports of another account are never reachable (the controller scopes them).
class EmailCampaignTemplateImportPolicy < ApplicationPolicy
  def create?
    manage?
  end

  def show?
    manage? && own?
  end

  def save?
    manage? && own?
  end

  private

  def manage?
    account_user&.permission_granted?('campaign_manage')
  end

  def own?
    record.account_id == account.id
  end
end
