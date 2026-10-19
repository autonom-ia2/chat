module Enterprise::ContactPolicy
  include Relationships::RecordPermissions

  def create?
    relationship_record_write?
  end

  def update?
    relationship_record_write?
  end

  def avatar?
    update?
  end

  def destroy_custom_attributes?
    update?
  end

  # Exporting the base left contact_manage in #1845; the migration gave contact_export to roles that had it.
  def export?
    @account_user.permission_granted?('contact_export')
  end

  def destroy?
    @account_user.permission_granted?('contact_delete')
  end

  def import?
    @account_user.custom_role&.permissions&.include?('contact_manage') || super
  end
end
