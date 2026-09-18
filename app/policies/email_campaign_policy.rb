class EmailCampaignPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def show?
    administrator? && record.account_id == account.id
  end

  def create?
    administrator?
  end

  def update?
    show?
  end

  def destroy?
    show?
  end

  def send_now?
    show?
  end

  def schedule?
    show?
  end

  def pause?
    show?
  end

  def resume?
    show?
  end

  def reevaluate?
    show?
  end

  def recheck?
    show?
  end

  def cancel?
    show?
  end

  def duplicate?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
