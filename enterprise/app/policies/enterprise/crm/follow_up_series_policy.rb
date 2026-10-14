# #1460 — funções personalizadas: ver a série pede crm_view; pausar, retomar, encerrar e mudar pedem
# crm_manage_cards, como os lembretes (Enterprise::Crm::FollowUpPolicy).
module Enterprise::Crm::FollowUpSeriesPolicy
  include CrmPermissions

  def show?
    crm_permission?('crm_view') && super
  end

  def update?
    crm_permission?('crm_manage_cards') && super
  end
end
