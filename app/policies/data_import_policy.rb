# Importing from another system takes that system's key (#2027): admin or integration_manage.
# A contact CSV import follows the contact import permission (upstream #16541).
class DataImportPolicy < ApplicationPolicy
  def index?
    contact_import? || integration_import?
  end

  def show?
    record.account_id == account.id && (record.data_type == 'contacts' ? contact_import? : integration_import?)
  end

  def create?
    record.is_a?(DataImport) ? show? : index?
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

  def rejected_rows?
    show?
  end

  def contact_import?
    ContactPolicy.new(user_context, Contact).import?
  end

  # Fork (upgrade 4.20.1, #3120): upstream #16541 asks administrator here; the fork keeps its key (#2027), so a custom
  # role with integration_manage keeps importing from other systems. The data_import flag moved here from the controller.
  def integration_import?
    account_user.permission_granted?('integration_manage') && account.feature_enabled?('data_import')
  end

  class Scope < Scope
    def resolve
      imports = scope.where(account_id: account.id)
      return imports if DataImportPolicy.new(user_context, DataImport).integration_import?
      return imports.where(data_type: 'contacts') if ContactPolicy.new(user_context, Contact).import?

      scope.none
    end
  end
end
