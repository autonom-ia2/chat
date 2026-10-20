module Enterprise::Audit::CustomRole
  extend ActiveSupport::Concern

  # Creating, changing and deleting a role changes the access of everyone who holds it (#1931).
  included do
    audited associated_with: :account
    # `dependent: :nullify` clears the holders in one SQL update, without callbacks: each holder's change is recorded
    # here. Prepended so it runs before the nullify.
    before_destroy :audit_released_holders, prepend: true
  end

  private

  def audit_released_holders
    account_users.find_each do |account_user|
      Enterprise::AuditLog.create!(
        auditable: account_user,
        action: 'update',
        associated: account,
        audited_changes: { 'custom_role_id' => [id, nil] },
        user: Current.user
      )
    end
  end
end
