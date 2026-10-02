# Shared records have separate write permission from CRM opportunities.
# Preserve the native administrator/plain-agent contract; granular keys apply
# to custom roles only. Deletion continues to use the existing admin-only policy.
module Relationships::RecordPermissions
  private

  def relationship_record_write?
    return false unless account_user
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.permission_granted?('contact_manage')
  end
end
