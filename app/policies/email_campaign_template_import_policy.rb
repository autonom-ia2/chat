# Importar modelo (#1099, delivery B): whoever manages campaigns imports, follows and saves — the same key that
# creates templates in "Meus modelos"; the screens (delivery C) also list the person's last import and fix one. Imports
# of another account are never reachable (the controller scopes them).
class EmailCampaignTemplateImportPolicy < ApplicationPolicy
  def index?
    manage?
  end

  def create?
    manage?
  end

  def fix?
    manage? && own?
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
