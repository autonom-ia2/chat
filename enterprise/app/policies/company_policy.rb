class CompanyPolicy < ApplicationPolicy
  include Relationships::RecordPermissions

  def index?
    true
  end

  def summary?
    index?
  end

  def search?
    true
  end

  def show?
    true
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
    @account_user.administrator?
  end
end
