class CompanyPolicy < ApplicationPolicy
  include Relationships::RecordPermissions

  def index?
    relationship_record_read?
  end

  def summary?
    index?
  end

  def search?
    relationship_record_read?
  end

  def show?
    relationship_record_read?
  end

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

  def destroy?
    @account_user.permission_granted?('contact_delete')
  end
end
