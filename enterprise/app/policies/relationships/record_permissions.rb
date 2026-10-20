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

  # Listing the Contacts module (lists, segments, filters) needs contact_view on a custom
  # role (#1157). Reading one record from a conversation or card, and the search used to
  # start a conversation or link a contact, stay open: they belong to the operation.
  def relationship_list_read?
    return false unless account_user
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.permission_granted?('contact_view')
  end
end
