module Enterprise::Crm::CardPolicy
  include CrmPermissions

  def index?
    crm_permission?('crm_view')
  end

  def export?
    crm_permission?('crm_export')
  end

  def show?
    crm_permission?('crm_view') && super
  end

  def create?
    crm_permission?('crm_manage_cards')
  end

  def update?
    crm_permission?('crm_manage_cards') && show?
  end

  def destroy?
    update?
  end

  def move?
    (crm_permission?('crm_move_cards') || crm_permission?('crm_manage_cards')) && show?
  end

  def from_conversation?
    create?
  end

  def link_conversation?
    update?
  end

  def unlink_conversation?
    update?
  end

  def link_contact?
    update?
  end

  def unlink_contact?
    update?
  end

  def evaluate_ai?
    crm_permission?('crm_manage_ai') && show?
  end

  def summarize?
    crm_permission?('crm_manage_ai') && show?
  end

  def reset_auto_followup?
    crm_permission?('crm_manage_ai') && show?
  end

  def current_ai_suggestion?
    crm_permission?('crm_view') && show?
  end
end
