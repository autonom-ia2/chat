class EmailProtectionMaintenancePolicy < ApplicationPolicy
  def self.platform_admin?(actor)
    actor.is_a?(User) && actor.persisted? && User.exists?(id: actor.id, type: 'SuperAdmin')
  end

  def self.authorized?(actor, account_id)
    ActiveRecord::Base.uncached do
      platform_admin?(actor) && Account.exists?(id: account_id, status: :active) &&
        AccountUser.exists?(account_id: account_id, user_id: actor.id)
    end
  end

  def create?
    self.class.authorized?(user, account.id)
  end

  def show?
    create? && record.account_id == account.id
  end

  def retry?
    show?
  end
end
