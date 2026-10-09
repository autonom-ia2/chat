class EmailReputationPolicy < ApplicationPolicy
  def show?
    account_user&.administrator? && record.id == account.id
  end

  def reevaluate?
    show?
  end

  def history?
    override?
  end

  def provider_release?
    override?
  end

  def override?
    record.id == account.id && user && SuperAdmin.exists?(id: user.id)
  end
end
