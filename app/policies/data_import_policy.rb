# Importing from another system takes that system's key (#2027): admin or integration_manage.
class DataImportPolicy < ApplicationPolicy
  def index?
    @account_user.permission_granted?('integration_manage')
  end

  def show?
    index? && record.account_id == account.id
  end

  def create?
    index?
  end

  def validate_source?
    create?
  end

  def start?
    show?
  end

  def retry_import?
    show?
  end

  def abandon?
    show?
  end

  def skip_logs?
    show?
  end

  def error_logs?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.where(account_id: account.id) if account_user.permission_granted?('integration_manage')

      scope.none
    end
  end
end
