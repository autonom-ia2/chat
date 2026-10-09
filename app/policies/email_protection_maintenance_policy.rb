class EmailProtectionMaintenancePolicy < ApplicationPolicy
  def self.platform_admin?(actor)
    actor.is_a?(SuperAdmin) && actor.persisted? && SuperAdmin.exists?(id: actor.id)
  end

  def create?
    self.class.platform_admin?(user)
  end

  def show?
    create? && record.account_id == account.id
  end

  def retry?
    show?
  end
end
