module Enterprise::Crm::FollowUpPolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_view')
  end

  def show?
    crm_permission?('crm_view') && super
  end

  def create?
    crm_permission?('crm_manage_cards')
  end

  def update?
    crm_permission?('crm_manage_cards') && show? && card_funnel_member?
  end

  def destroy?
    update?
  end

  def complete?
    update?
  end

  def cancel?
    update?
  end

  def dismiss_reminder?
    show?
  end
end
