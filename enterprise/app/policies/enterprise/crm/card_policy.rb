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

  # Acesso por funil (#1148): mexer no card exige o funil dele (Crm::CardPolicy#funnel_member?).
  def update?
    crm_permission?('crm_manage_cards') && show? && funnel_member?
  end

  # Arquivar tem chave própria (#1874, decisão 7.4-2): `crm_delete_cards`, um card ou vários.
  def destroy?
    crm_permission?('crm_delete_cards') && show? && funnel_member?
  end

  def move?
    (crm_permission?('crm_move_cards') || crm_permission?('crm_manage_cards')) && show? && funnel_member?
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
    crm_permission?('crm_manage_ai') && show? && funnel_member?
  end

  def summarize?
    crm_permission?('crm_manage_ai') && show? && funnel_member?
  end

  def reset_auto_followup?
    crm_permission?('crm_manage_ai') && show? && funnel_member?
  end

  def current_ai_suggestion?
    crm_permission?('crm_view') && show?
  end
end
