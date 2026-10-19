# Shared records have separate read and write permission from CRM opportunities.
# Preserve the native administrator/plain-agent contract; granular keys apply
# to custom roles only. Deletion needs contact_delete (or administrator), never plain agent (#1845).
module Relationships::RecordPermissions
  private

  # The contact base (lists, search, profile) needs contact_view; contact_manage implies it (#1849).
  def relationship_record_read?
    return false unless account_user
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.permission_granted?('contact_view')
  end

  def relationship_record_write?
    return false unless account_user
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.permission_granted?('contact_manage')
  end
end
