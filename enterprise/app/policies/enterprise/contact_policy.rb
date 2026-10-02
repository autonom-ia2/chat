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

  def export?
    @account_user.custom_role&.permissions&.include?('contact_manage') || super
  end

  def import?
    @account_user.custom_role&.permissions&.include?('contact_manage') || super
  end
end
